package ProxyTunnel;
use strict;
use PerlShareCommon::Dirs;
use PerlShareCommon::Constants;

sub new() {
  my $class = shift;
  my $obj = {};
  
  tie my %cfg, 'PerlShareCommon::Cfg', READ => global_conf();
  my $method = $cfg{main}{proxytunnel_method};
  if (not($method)) { $method = "corkscrew"; }
  
  if ($method ne "corkscrew" && $method ne "proxytunnel") {
  	die "ProxyTunnel needs corkscrew or proxytunnel as method";
  }
  
  $obj->{method} = $method;
  
  bless $obj, $class;
  
  return $obj;
}

sub proxy_option() { 
  my $self = shift;
  my $host = shift;
  my $port = shift;
  
  if (not($port)) { $port = 80; }
  if ($self->{method} eq "corkscrew") {
    return "ProxyCommand corkscrew $host $port localhost 22"
  } elsif ($self->{method} eq "proxytunnel") {
    my $user_agent = user_agent(); 
    return "ProxyCommand proxytunnel -q -p $host:80 -d localhost:22 -H \"$user_agent\"";
  } 
}

sub proxy_keep_alives() {
  my $os = $^O;
  my $keepalives = ($os=~/^MSWin/) ? "" : "ProtocolKeepAlives 5";
  return $keepalives;
}


1;

