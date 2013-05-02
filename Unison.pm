package Unison;
use Dirs;
use Log;
use strict;

sub new() {
  my $class = shift;
  my $unison_profile = shift;
  my $obj = {};
  
  $obj->{profile} = $unison_profile;
  
  bless $obj, $class;
  
  return $obj;
}

sub profile_file() {
  my $self = shift;
  my $unison_dir = unison_dir();
  my $profile = $self->{profile};
  return "$unison_dir/$profile.prf";
}

sub has_unison() {
  my $self = shift;
  return defined($self->version()); 
}

sub version() {
  my $self = shift;
  my $ssh_server = shift;
  my $ssh_user = shift;
  my $ssh_port = shift;
  
  my $cmd = "unison -version";
  if (defined($ssh_server)) {
    my $user = "";
    if (defined($ssh_user)) { $user = "$ssh_user".'@'; }
    my $port = "";
    if (defined($ssh_port)) { $port = " -p ".$ssh_port; }
    $cmd = "ssh -o \"StrictHostKeyChecking no\" $user$ssh_server$port unison -version";
  }
    
  open my $fh, "$cmd 2>&1 |";
  my $line=<$fh>;
  close $fh;
  
  $line =~ s/^\s*//;
  $line =~ s/\s*$//;
  my $log_line = $line;
  
  if (defined($line)) {
    if ($line =~ /^unison\s+version/i) {
      $line =~ s/^unison\s+version\s*//i;
      if ($line eq "") {
        log_error("Unison: cannot determine unison version");
        return undef;
      } else {
        log_info("Unison: determined unison version as $line");
        return $line;
      }
    } else {
      log_error("Unison: cannot determine unison version");
      log_error("Unison: info '$line'");
    }
  } else {
    log_error("Unison: cannot determine unison version");
    return undef;
  }
}

sub run() {
}

sub run_gui() {
}

sub server_version() {
  my $self = shift;
  my $prf = $self->profile_file();
  if (-r $prf) {
    return $self->version
  }
}


=pod
=head1 Unison

=head2 Introduction

This package controls a unison executable and a unison configuration file.
It does this and only this. 

=end

