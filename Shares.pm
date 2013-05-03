package Shares;
use Expect;
use PerlShareCommon::Dirs;
use PerlShareCommon::Log;
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

sub create_share() {
  my $self = shift;
  my $sharename = shift;
  my $host = shift;
  my $email = shift;
  my $pass = shift;
  
  mkdir(perlshare_dir($sharename));
  chmod(0755, perlshare_dir($sharename));
  mkdir(conf_dir($sharename));
  mkdir(unison_dir($sharename));
  
  log_info("####");
  log_info("Creating new share for host '$host', with email '$email'");
  log_info("####");
  
  my $sshkey_file = sshkey($sharename);
  my $sshkey_pub_file = pub_sshkey($sharename);
  
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
  $exp = Expect->new();
  $exp->raw_pty(1);
  $exp->log_stdout(0);
  $exp->log_file(\&log_info);
  $exp->spawn("cat \"$sshkey_pub_file\" | ssh -o \"StrictHostKeyChecking no\" -i \"$sshkey_file\" -l $email $host \"cat >>.ssh/authorized_keys2;echo OK\"");
  $exp->expect(10,"password:");
  $exp->send("$pass\n");
  my $patidx = $exp->expect(10,/OK/,/.*/);
  $exp->soft_close();

  my $result = 0;
  
  if ($patidx == 0) { # all went well
    my $prf_file = unison_dir($sharename)."/default.prf";
    log_info("Creating profile '$prf_file'");
    open my $fh, ">$prf_file";
    print $fh "root = ".perlshare_dir($sharename)."\n";
    print $fh "root = ssh://$host//home/perlshare/$email\n";
    print $fh "sshargs = -i $sshkey_file -l $email -C\n";
    print $fh "ignore = Path .*\n";
    print $fh "follow = Regex .*\n";
    print $fh "fastcheck = true\n";
    close($fh);
    
    $self->{message} = "Success";
    $result = 1;
  } else { # anything else means we didn't succeed
    $self->{message} = "Could not create the share with the given credentials, check log";
    $result = 0;
  }
  
  # Check if unison is there and unison versions
  log_info("Checking consistency of unison versions");
  my $unison_ctrl = new Unison();
  if ($unison_ctrl->has_unison()) {
    my $local_version = $unison_ctrl->version();
    my $remote_version = $unison_ctrl->version($host, $email);
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
    my %cfg = global_conf();
    tie my %cfg, 'PerlShareCommon::Cfg', READ => global_conf(), WRITE => global_conf();
    my $num_of_shares = $cfg{shares}{count} or 0;
    $cfg{shares}{share}[$num_of_shares] = $sharename;
    $cfg{shares}{count} = $num_of_shares + 1;
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

1;

