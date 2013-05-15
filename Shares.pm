package Shares;
use strict;
use POSIX qw(:fcntl_h);
use PerlShareCommon::Dirs;
use PerlShareCommon::Log;
use PerlShareCommon::Str;
use PerlShareCommon::Constants;
use PerlShareCommon::WatchDirectoryTree;
use SshCmd;
use IO::Socket::SSL qw( SSL_VERIFY_NONE );
use LWP::Simple;
use Unison;

sub new() {
  my $class = shift;
  my $obj = {};
  
  $obj->{message} = "";
  mkdir(global_conf_dir());
  
  tie my %cfg, 'PerlShareCommon::Cfg', READ => global_conf();
  
  my $sleep_time = $cfg{main}{sync_sleep};
  if ($sleep_time <= 0) { $sleep_time = 30; }
  elsif ($sleep_time < 10) { $sleep_time = 10; }
  
  $obj->{sleep_time} = $sleep_time;
  untie %cfg;
  
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

sub check_share_host() {
  my $self = shift;
  my $share = shift;
  my $host = shift;
  my $email = shift;
  my $pass = shift;
  
  my $checker = sub {
    my $url = shift;
    log_info("Checking $url for user '$email' and share '$share'");
    my $browser = LWP::UserAgent->new();
    $browser->ssl_opts(
      SSL_verify_hostname => 0,
      SSL_verify_mode => SSL_VERIFY_NONE
    );
    my $response = $browser->post(
          $url, 
          [ 'share' => $share,
            'email' => $email,
            'pass' => $pass
          ]
    );
    
    if (not($response->is_success)) {
      log_error("Error at $url - '".$response->status_line."' Aborting");
      return "Can't reach host '$host'";
    }
    
    my $content = $response->content();
    log_info($content);
    
    if ($content =~ /OKOKOK/) {
      return undef;
    } else {
      return "User '$email' is not registered or wrong credentials have been given";
    } 
  };
  
  $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
  my $result = $checker->("https://$host/check_user.php", $host);
  if ($result=~/^Can[']t[ ]reach[ ]host/) {
    my $r1 = $checker->("https://$host/perlshare/check_user.php", $host);
    if ($r1=~/^Can[']t[ ]reach[ ]host/) {
      return $result;
    } else {
      return $r1;
    }
  } else {
    return $result;
  }
}

sub push_public_key() {
  my $self = shift;
  my $share = shift;
  my $host = shift;
  my $email = shift;
  my $pass = shift;
  my $keyfile = shift;
  
  open my $fh, "<$keyfile.pub";
  my $key = "";
  while(my $line = <$fh>) {
    $key .= $line;
  }
  close($fh);
  
  my $checker = sub {
    my $url = shift;
    log_info("Checking $url for user '$email' and share '$share'");
    my $browser = LWP::UserAgent->new();
    $browser->ssl_opts(
      SSL_verify_hostname => 0,
      SSL_verify_mode => SSL_VERIFY_NONE
    );
    my $response = $browser->post(
          $url, 
          [ 'share' => $share,
            'email' => $email,
            'pass' => $pass,
            'key' => $key
          ]
    );
    
    if (not($response->is_success)) {
      log_error("Error at $url - '".$response->status_line."' Aborting");
      return "Can't reach host";
    }
    
    my $content = $response->content();
    log_info($content);
    
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME}=0;
    if ($content =~ /OKOKOK/) {
      return undef;
    } else {
      return "User not registered or wrong credentials given";
    } 
  };
  
  my $result = $checker->("https://$host/push_key.php");
  if ($result eq "Can't reach host") {
    return $checker->("https://$host/perlshare/push_key.php");
  } else {
    return $result;
  }
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
  my $message = $self->check_share_host($sharename, $host, $email, $pass);
  if (defined($message)) {
    log_error($message);
    $self->{message} = $message;
    log_info("####");
    return 0;
  }
  
  my $sshkey_file;
  my $ssh = new SshCmd();
  my $fh;

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
    $ssh->create_keyfile($sshkey_file);
  }
  
  # Check if we already can reach the host with this key
  log_info("Pushing public key to server $host for user $email");
  my $result = 1;
  $message = $self->push_public_key($sharename, $host, $email, $pass, $sshkey_file);
  if (defined($message)) {
    log_error($message);
    $self->{message} = $message;
    log_info("####");
    $result = 0;
  }
  
  if ($result) {
    my $prf_file = unison_dir($locshare)."/default.prf";
    my $sshconfig = unison_dir($locshare)."/sshconfig";

    log_info("Creating profile '$prf_file'");
    my $os = $^O;
    
    $ssh->create_ssh_config($sshconfig, $host, $email, $sshkey_file);

    my $perlsharemerge = my_dir()."/PerlShareMerge.pl";
    my $sharedir = perlshare_dir($locshare);
    open $fh, ">$prf_file";
    print $fh "root = $sharedir\n";
    print $fh "root = ssh://$host//home/perlshare/$email/$sharename\n";
    if ($os=~/MSWin/) {
      print $fh "sshargs = -F '$sshconfig' -l $email\n";
    } else {
      print $fh "sshargs = -F $sshconfig -l $email\n";
    }
    print $fh "ignore = Path .*\n";
    print $fh "follow = Regex .*\n";
    print $fh "fastcheck = true\n";
    #print $fh "copythreshold = 1000\n"; # Later, because it also needs
    # special ssh handling
    print $fh "fat = true\n";
    print $fh "dontchmod = false\n";
    print $fh "perms = 0\n";
    print $fh "merge = Name * -> perl $perlsharemerge \"$sharedir\" \"PATH\" \"CURRENT1\" \"CURRENT2\" \"NEW\"\n";
    print $fh "servercmd = /usr/share/perlshare/unison_umask\n";
    close($fh);
    
    $self->{message} = "Success";
    my $result = 1;
  }
  
  if ($result) {
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
  }
  
  # put share in config
  if ($result) {
    log_info("Adding share to configuration");
    tie my %cfg, 'PerlShareCommon::Cfg', READ => global_conf(), WRITE => global_conf();
    my $num_of_shares = $cfg{shares}{count};
    if (not(defined($num_of_shares))) { $num_of_shares = 0; }
    
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

sub drop_local() {
  my $self = shift;
  my $share = shift;
  tie my %cfg, 'PerlShareCommon::Cfg', READ => global_conf(), WRITE => global_conf();
  my $num_of_shares = $cfg{shares}{count};
  if (not(defined($num_of_shares))) { $num_of_shares = 0; }
  my $i = 0;
  my $k = 0;
  while ($i < ($num_of_shares - 1)) {
    if ($cfg{shares}{share}[$i] eq $share) {
      # skip
    } else {
      $cfg{shares}{share}[$k] = $cfg{shares}{share}[$i];
      $k += 1;
    }
    $i += 1;
  }
  $cfg{shares}{share}[$i] = undef;
  $cfg{shares}{count} = $num_of_shares - 1;
  untie %cfg;
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
  
  my $ssh = new SshCmd();
  my $cmd = $ssh->ssh_cmd($host, $email, "cat /home/perlshare/$email/$remote_share/.count", $keyfile);
  
  my $log2 = temp_dir()."/perlsharecheck.err";
  open my $fh, "$cmd 2>\"$log2\" |";
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

sub get_share_info() {
  my $shares = shift;
  my $share = shift;
  
  tie my %cfg, 'PerlShareCommon::Cfg', READ => global_conf();
  my $host = $cfg{data}{$share}{host};
  my $keyfile = $cfg{data}{$share}{keyfile};
  my $email = $cfg{data}{$share}{email};
  my $local_share = $cfg{data}{$share}{local};
  my $remote_share = $cfg{data}{$share}{remote};
  untie %cfg;
  
  return ($host, $email, $local_share, $remote_share, $keyfile);
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
  
  my $ssh = new SshCmd();
  my $cmd = $ssh->ssh_cmd($host, $email, 
                          "echo $count >/home/perlshare/$email/$remote_share/.count;".
                            "chmod 664 /home/perlshare/$email/$remote_share/.count",
                          $keyfile
                          );
  my $log2 = temp_dir()."/perlsharecheck.err";
  open $fh, "$cmd 2>$log2 |";
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
         
          log_info("done syncing"); 
          # flush watcher after sync
          $watcher->get_directory_changes();

          log_info("got directory changes");
        }
        $first_time = 0;
        log_info("sleeping ".$self->{sleep_time}." seconds");
        sleep($self->{sleep_time});
      }
    }
  );
  $thr->detach();
}

1;

