package SshCmd;
use strict;
use PerlShareCommon::Dirs;
use PerlShareCommon::Log;
use PerlShareCommon::Constants;
use ProxyTunnel;

sub new() {
  my $class = shift;
  my $obj = {};
  
  $obj->{proxytunnel} = new ProxyTunnel();
  
  bless $obj, $class;
  return $obj;
}

sub create_ssh_config() {
  my ($self, $sshconfig_file, $host, $email, $keyfile) = @_;

  my $pt = $self->{proxytunnel};

  my $proxy_option = $pt->proxy_option($host);
  my $keepalive_option = $pt->proxy_keey_alives();
  
  open my $fh, ">$sshconfig_file";
  print $fh "StrictHostKeyChecking no\n";
  print $fh "$proxy_option\n";
  if ($keepalive_option) {
    print $fh "$keepalive_option\n";
  }    
  print $fh "IdentityFile \"$keyfile\"\n";
  close($fh);
}

sub ssh_cmd() {
  my ($self, $host, $email, $cmd, $keyfile) = @_;
  my $pt = $self->{proxytunnel};
  
  my $proxy_option = $pt->proxy_option($host);
  my $keepalive_option = $pt->proxy_keep_alives();
  if ($keepalive_option) { $keepalive_option = "-o '$keepalive_option' "; }
  $ENV{CYGWIN} = "nodosfilewarning";  # win32
  
  my $sshcmd="ssh -o 'StrictHostKeyChecking no' ".
                 "-o '$proxy_option' ".
                 "$keepalive_option".
                 "-i \"$keyfile\" -l $email $host ".
                 "\"$cmd\"";
  #log_debug($sshcmd);
  return $sshcmd;
}

sub create_keyfile() {
  my $self = shift;
  my $keyfile = shift;
  
  $ENV{CYGWIN} = "nodosfilewarning";
  open my $fh, "ssh-keygen -t rsa -N \"\" -f \"$keyfile\" 2>&1 |";
  while (my $line = <$fh>) {
    log_info($line);
  }
  close($fh);
}


1;

