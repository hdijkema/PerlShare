package Shares;
use strict;
use POSIX qw(:fcntl_h);
#use Expect;
#use Net::OpenSSH;
use Net::SSH2;  
use PerlShareCommon::Dirs;
use PerlShareCommon::Log;
use PerlShareCommon::Str;
use PerlShareCommon::Constants;
use PerlShareCommon::WatchDirectoryTree;
use Unison;

sub new() {
  my $class = shift;
  my $obj = {};
  
  $obj->{message} = "";
  mkdir(global_conf_dir());
  
  bless $obj, $class;
  
  return $obj;
}

sub get_shares() {
  my $self = shift;
  tie my %cfg, 'PerlShareCommon::Cfg', READ => global_conf();
  my $count = $cfg{shares}{count} or 0;
  my $i = 0;
  my @shares;
  while ($i < $count) {
    push @shares, $cfg{shares}{share}[$i];
    $i += 1;
  }
  return @shares;
}

sub associate() {
  my $self = shift;
  my $share = shift;
  my $type = shift;
  my $obj = shift;
  
  my $assoc = {};
  if (defined($self->{"assoc_$share"})) {
    $assoc = $self->{"assoc_$share"};
  }
    
  $assoc->{$type} = $obj;
  $self->{"assoc_$share"} = $assoc;
}

sub get_assoc() {
  my $self = shift;
  my $share = shift;
  my $type = shift;

  my $assoc = {};
  if (defined($self->{"assoc_$share"})) {
    $assoc = $self->{"assoc_$share"};
  }
  
  return $assoc->{$type};
}

sub create_share() {
  my $self = shift;
  my $sharename = shift;
  my $host = shift;
  my $email = shift;
  my $pass = shift;
  my $locshare = shift;
  
  if (not($locshare)) { $locshare = $sharename; } 
  
  log_info("####");
  log_info("Creating new share for host '$host', with email '$email'");
  log_info("####");
  
  # First check if we can reach the host
  log_info("Checking access to $host for user $email (share=$sharename, local=$locshare)");
  {
    my $cmd = "perl ".my_dir()."/PerlCheckSSH.pl $sharename $host $email $pass";
    open my $fh, "$cmd 2>&1 |";
    while (my $line = <$fh>) {
      log_info($line);
    }
    close($fh);
    my $exit_code = $? / 256;
    log_info("exitcode = $exit_code");
    if ($exit_code == 1) {
      $self->{message} = "Cannot reach host";
      log_error($self->{message});
      log_info("####");
      return 0;
    } elsif ($exit_code == 2) {
      $self->{message} = "user not registered or wrong credentials, check logs";
      log_error($self->{message});
      log_info("####");
      return 0;
    }
  }
  
  my $sshkey_file;

  # Go on and create
  mkdir(perlshare_dir($locshare));
  chmod(0755, perlshare_dir($locshare));
  mkdir(conf_dir($locshare));
  mkdir(unison_dir($locshare));
  
  my $sshkey_file = sshkey($locshare);
  my $sshkey_pub_file = pub_sshkey($locshare);
  
  # Create a new sshkey if necessary
  log_info("Creating RSA key at $sshkey_file");
  if (! -r $sshkey_file) {
    open my $fh, "ssh-keygen -t rsa -N \"\" -f \"$sshkey_file\" 2>&1 |";
    while (my $line = <$fh>) {
      log_info($line);
    }
    close($fh);
  }
  
  # Check if we already can reach the host with this key
  log_info("Pushing public key to server $host for user $email");
  my $result = 1;
  
  {
    my $cmd = "perl ".my_dir()."/PerlCheckSSH.pl $sharename $host $email $pass $sshkey_pub_file";
    open my $fh, "$cmd 2>&1 |";
    while (my $line = <$fh>) {
      log_info($line);
    }
    close($fh);
    my $exit_code = $? / 256;
    log_info("exitcode = $exit_code");
    if ($exit_code != 0) {
      $self->{message} = "Cannot push public key to server, no sftp connection";
      $result = 0;
    }
  }
  
  if ($result) {
    my $prf_file = unison_dir($locshare)."/default.prf";
    my $sshconfig = unison_dir($locshare)."/sshconfig";

    log_info("Creating profile '$prf_file'");
    
    open my $fh, ">$sshconfig";
    print $fh "ProxyCommand proxytunnel -q -p $host:80 -d localhost:22 -H \"User-Agent: Mozilla/4.0 (compatible; MSIE 6.0; Win32\"\n";
    print $fh "ProtocolKeepAlives 5\n";
    print $fh "IdentityFile $sshkey_file\n";
    close($fh);

    my $perlsharemerge = my_dir()."/PerlShareMerge.pl";
    my $sharedir = perlshare_dir($locshare);
    open $fh, ">$prf_file";
    print $fh "root = $sharedir\n";
    print $fh "root = ssh://$host//home/perlshare/$email/$sharename\n";
    print $fh "sshargs = -F $sshconfig -l $email\n";
    print $fh "ignore = Path .*\n";
    print $fh "follow = Regex .*\n";
    print $fh "fastcheck = true\n";
    print $fh "fat = true\n";
    print $fh "dontchmod = false\n";
    print $fh "perms = 0\n";
    print $fh "merge = Name * -> perl $perlsharemerge '$sharedir' 'PATH' 'CURRENT1' 'CURRENT2' 'NEW'\n";
    print $fh "servercmd = /usr/share/perlshare/unison_umask\n";
    close($fh);
    
    $self->{message} = "Success";
    my $result = 1;
  }
  
  # Check if unison is there and unison versions
  log_info("Checking consistency of unison versions");
  my $unison_ctrl = new Unison();
  if ($unison_ctrl->has_unison()) {
    my $local_version = $unison_ctrl->version();
    my $remote_version = $unison_ctrl->version($host, $sshkey_file, $email);
    log_info("Unison: local version: $local_version");
    log_info("Unison: remote version: $remote_version");
    if ($local_version ne $remote_version) {
      log_error("Unison: local and remote versions differ!");
      $self->{message} = "The local and remote versions of PerlShare differ. Make sure they are the same.";
      $result = 0;
    }
  } else {
    log_error("No unison installed!");
    $self->{message} = "You need unison installed for PerlShare to work";
    $result = 0;
  }
  
  # put share in config
  if ($result != 0) {
    log_info("Adding share to configuration");
    tie my %cfg, 'PerlShareCommon::Cfg', READ => global_conf(), WRITE => global_conf();
    my $num_of_shares = $cfg{shares}{count} or 0;
    $cfg{shares}{share}[$num_of_shares] = $locshare;
    $cfg{shares}{count} = $num_of_shares + 1;
    
    $cfg{data}{$locshare}{host} = $host;
    $cfg{data}{$locshare}{keyfile} = $sshkey_file;
    $cfg{data}{$locshare}{email} = $email;
    $cfg{data}{$locshare}{local} = $locshare;
    $cfg{data}{$locshare}{remote} = $sharename;
    
    untie %cfg;
  }
  
  log_info($self->{message});
  log_info("####");
  
  return $result;
}

sub get_message() {
  my $self = shift;
  return $self->{message};
}

sub set_last_sync() {
  my $self = shift;
  my $share = shift;
}

# if a client has local changes, it will push these changes to the server
# along with it, it will update a .count file in the share. 
# if the local .count file < the remote .count file, 
# we need to synchronize and update the .count file to the latest.
# while synchronizing we need to ignore changes to the filesystem
#
sub check_last_sync() {
  my $self = shift;
  my $share = shift;
  
  tie my %cfg, 'PerlShareCommon::Cfg', READ => global_conf();
  my $host = $cfg{data}{$share}{host};
  my $keyfile = $cfg{data}{$share}{keyfile};
  my $email = $cfg{data}{$share}{email};
  my $local_share = $cfg{data}{$share}{local};
  my $remote_share = $cfg{data}{$share}{remote};
  untie %cfg;

  log_info("checking share '$share', host=$host, email=$email");
  # We need to check for each top directory if the count has changed.
  
  my $user_agent = user_agent(); 

  my $cmd = "ssh ".
                 "-o 'ProxyCommand proxytunnel -q -p $host:80 -d localhost:22 -H \"$user_agent\"' ".
                 "-o 'ProtocolKeepAlives 5' ".
                 "-i \"$keyfile\" -l $email $host ".
                 "cat /home/perlshare/$email/$remote_share/.count";

  open my $fh, "$cmd 2>/dev/null |";
  my $remote_count = <$fh>;
  $remote_count = trim($remote_count);
  if (not($remote_count)) { $remote_count = -1; }
  close($fh);
  my $exit_code = $? / 256;
  
  log_info("exitcode = $exit_code");
  if ($exit_code != 0) {
    log_warn("Cannot connect host for sync checking");
    return (-1, undef, undef);
  }
  
  my $localshr = perlshare_dir($local_share);
  open $fh, "<$localshr/.count";
  my $local_count = <$fh>;
  $local_count = trim($local_count);
  close($fh);
  if (not($local_count)) { $local_count = 0; }
  
  my $conflict = 0;
  if (-e "$localshr/.conflict") {
    unlink("$localshr/.conflict");
    $conflict = 1;
  }
  
  if ($remote_count != $local_count || $conflict) {
    return (1, $remote_count, $local_count);
  } else {
    return (0, $remote_count, $local_count);
  }
}

sub sync_now() {
  my $self = shift;
  my $share = shift;
  my $cb_func = shift;
  my $remote_count = shift;
  my $local_count = shift;

  tie my %cfg, 'PerlShareCommon::Cfg', READ => global_conf();
  my $host = $cfg{data}{$share}{host};
  my $keyfile = $cfg{data}{$share}{keyfile};
  my $email = $cfg{data}{$share}{email};
  my $local_share = $cfg{data}{$share}{local};
  my $remote_share = $cfg{data}{$share}{remote};
  untie %cfg;
  
  my $unison = new Unison();
  $unison->run($share, $cb_func);

  my $count = ($remote_count > $local_count) ? $remote_count-1 : $local_count;
  $count += 1;
  
  my $localshr = perlshare_dir($local_share);
  open my $fh, ">$localshr/.count";
  print $fh "$count\n";
  close($fh);
  
  my $user_agent = user_agent();
  
  my $cmd = "ssh ".
                 "-o 'ProxyCommand proxytunnel -q -p $host:80 -d localhost:22 -H \"$user_agent\"' ".
                 "-o 'ProtocolKeepAlives 5' ".
                 "-i \"$keyfile\" -l $email $host ".
                 "\"echo $count >/home/perlshare/$email/$remote_share/.count;chmod 664 /home/perlshare/$email/$remote_share/.count\"";
      
  open $fh, "$cmd 2>/dev/null |";
  while (my $line = <$fh>) {
    log_info($line);
  }
  close($fh);
}

# This is the synchronized gardian.
sub synchronizer() {
  my $self = shift;
  my $cb = shift;
  
  my $thr = threads->create(
    sub {
      my $shares = new Shares();
      log_info("Starting synchronizer for all shares");
      my $first_time = 1;
      while ( 1 ) {
        my @S = $shares->get_shares();
        foreach my $share (@S) {
          tie my %cfg, 'PerlShareCommon::Cfg', READ => global_conf();
          my $local_share = $cfg{data}{$share}{local};
          untie %cfg;
          my $dir = perlshare_dir($local_share);
          my $watcher = $shares->get_assoc($share, "watcher");
          if (defined($watcher)) {
            if ($watcher->get_directory_changes()) {
              open my $fh, "<$dir/.count";
              my $cnt = <$fh>;
              log_info("count = $cnt");
              trim($cnt);
              close($fh);
              $cnt += 1;
              open $fh, ">$dir/.count";
              print $fh "$cnt\n";
              close($fh);
            }
          } else {
            $watcher = new PerlShareCommon::WatchDirectoryTree($dir);
            $shares->associate($share, "watcher", $watcher);
          }
          
          my ($sync, $remote_count, $local_count) = $shares->check_last_sync($share);
          if ($sync == -1) { 
            # We cannot 
            $cb->($share, "disconnected", -1);
          } elsif ($sync || $first_time) {
            # we can connect, and need to sync
            $cb->($share, "connected", 0);
            $shares->sync_now($share, $cb, $remote_count, $local_count);
          } else {
            # we can connect, but don't need to sync
            $cb->($share, "connected", 0);
          }
          
          # flush watcher after sync
          $watcher->get_directory_changes();
        }
        $first_time = 0;
        sleep(10);
      }
    }
  );
  $thr->detach();
}

1;

