package Shares;
use strict;
use POSIX qw(:fcntl_h);
#use Expect;
#use Net::OpenSSH;
use Net::SSH2;  
use PerlShareCommon::Dirs;
use PerlShareCommon::Log;
use Unison;
use PerlShareCommon::Str;

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
  
  #my $ssh = Net::OpenSSH->new($host, 
  #                            user => $email, 
  #                            passwd => $pass, 
  #                            default_ssh_opts => [-o => "StrictHostKeyChecking no" ]
  #                            );
  my $ssh2 = Net::SSH2->new();
  my $connected = 1;
  $ssh2->connect($host) or $connected = 0;
  if ($connected) {
    if ($ssh2->auth_password($email, $pass)) {
      log_info("Logged in to $host");
    } else {
      $self->{message} = "user not registered or wrong credentials, check logs";
      log_error($self->{message});
      log_info("####");
      return 0;
    }
  } else {
    $self->{message} = "Cannot reach host";
    log_error($self->{message});
    log_info("####");
    return 0;
  }
  
  
  #my $exp;
  #$exp = Expect->new();
  #$exp->raw_pty(1);
  #$exp->log_stdout(0);
  #$exp->log_file(\&log_info);
  #$exp->debug(1);
  my $sshkey_file;
  #my $cmd = "ssh -o \"StrictHostKeyChecking no\" -l $email $host \"echo 'OKOKOK'\"";
  #log_info("cmd = $cmd");
  #$exp->spawn($cmd);
  
  #my $patidx;
  #$patidx = $exp->expect(3,"password:", "OKOKOK");
  #log_info("patidx = $patidx");
  #if ($patidx == 1) {
  #  $exp->send("$pass\n");
  #  $patidx = $exp->expect(3, 'OKOKOK');
  #} 
  
  #$exp->soft_close();
  #log_info("patidx = $patidx");

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
  #$exp = Expect->new();
  #$exp->raw_pty(1);
  #$exp->log_stdout(0);
  #$exp->log_file(\&log_info);
  #$exp->spawn("cat \"$sshkey_pub_file\" | ssh -o \"StrictHostKeyChecking no\" -i \"$sshkey_file\" -l $email $host \"cat >>.ssh/authorized_keys2;echo OKOKOK\"");
  
  #$patidx = $exp->expect(3,"password:", "OKOKOK");
  #log_info("patidx = $patidx");
  #if ($patidx == 1) {
  #  $exp->send("$pass\n");
  #  $patidx = $exp->expect(3, 'OKOKOK');
  #} 
  my $result = 1;
  
  #my $sftp = $ssh2->sftp();
  #if ($sftp) {
  #  my $sfh = $sftp->open("tst", O_APPEND|O_CREAT);
  #  if ($sfh) {
  #    open my $fh, "<$sshkey_pub_file";
  #    while (my $line = <$fh>) {
  #      log_info($line);
  #      my $bytes = print $sfh $line;
  #      log_info("written: $bytes bytes");
  #    }
  #    close $fh;
  #    close $sfh;
  #  } else {
  #    $self->{message} = "Cannot push public key to server, couldn't open authorized_keys2 ";
  #    $result = 0;
  #  }
  my $session = $ssh2->channel();
  if ($session) {
    $session->exec("cat >>.ssh/authorized_keys2");
    open my $fh, "<$sshkey_pub_file";
    while (my $line = <$fh>) {
      log_info($line);
      my $bytes = $session->write($line);
      log_info("written: $bytes bytes");
      $session->flush();
    }
    $session->close();
    $session = $ssh2->channel();
    $session->exec("mkdir -p /home/perlshare/$email/$sharename");
    $session->close();
    $session = $ssh2->channel();
    $session->exec("echo -10 >/home/perlshare/$email/$sharename/.count");
    $session->close();
  } else {
    $self->{message} = "Cannot push public key to server, no sftp connection";
    $result = 0;
  }
  
  #$exp->soft_close();

  #if (not(defined($patidx))) { $patidx = 1; }
  
  #if ($patidx == 1) { # all went well
  if ($result) {
    my $prf_file = unison_dir($locshare)."/default.prf";
    log_info("Creating profile '$prf_file'");
    open my $fh, ">$prf_file";
    print $fh "root = ".perlshare_dir($locshare)."\n";
    print $fh "root = ssh://$host//home/perlshare/$email/$sharename\n";
    print $fh "sshargs = -i $sshkey_file -l $email -C\n";
    print $fh "ignore = Path .*\n";
    print $fh "follow = Regex .*\n";
    print $fh "fastcheck = true\n";
    print $fh "fat = true\n";
    print $fh "dontchmod = false\n";
    print $fh "perms = 0\n";
    close($fh);
    
    $self->{message} = "Success";
    my $result = 1;
  }
  #} else { # anything else means we didn't succeed
  #  $self->{message} = "Could not create the share with the given credentials, check log";
  #  $result = 0;
  #}
  
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
  
  my $cmd = "ssh -o \"StrictHostKeyChecking no\" ".
                 "-i \"$keyfile\" -l $email $host ".
                 "cat /home/perlshare/$email/$remote_share/.count";

  open my $fh, "$cmd |";
  my $remote_count = <$fh>;
  $remote_count = trim($remote_count);
  if (not($remote_count)) { $remote_count = -1; }
  close($fh);
  
  my $localshr = perlshare_dir($local_share);
  open $fh, "<$localshr/.count";
  my $local_count = <$fh>;
  $local_count = trim($local_count);
  close($fh);
  if (not($local_count)) { $local_count = 0; }
  
  if ($remote_count != $local_count) {
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

  my $cmd = "ssh -o \"StrictHostKeyChecking no\" ".
                     "-i \"$keyfile\" -l $email $host ".
                     "\"echo $count >/home/perlshare/$email/$remote_share/.count\"";
      
  open $fh, "$cmd |";
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
          my ($sync, $remote_count, $local_count) = $shares->check_last_sync($share);
          if ($sync || $first_time) {
            $shares->sync_now($share, $cb, $remote_count, $local_count);
          }
        }
        $first_time = 0;
        sleep(10);
      }
    }
  );
  $thr->detach();
}

1;

