package Unison;
use PerlShareCommon::Dirs;
use PerlShareCommon::Log;
use strict;

sub new() {
  my $class = shift;
  my $obj = {};
  
  bless $obj, $class;
  
  return $obj;
}

sub has_unison() {
  my $self = shift;
  return defined($self->version()); 
}

sub version() {
  my $self = shift;
  my $ssh_server = shift;
  my $ssh_keyfile = shift;
  my $ssh_user = shift;
  my $ssh_port = shift;
  
  my $cmd = $self->unison_cmd("", "text"," -version");
  if (defined($ssh_server)) {
    my $user = "";
    if (defined($ssh_user)) { $user = "$ssh_user".'@'; }
    my $port = "";
    if (defined($ssh_port)) { $port = " -p ".$ssh_port; }
    $cmd = "ssh -i \"$ssh_keyfile\" -o \"StrictHostKeyChecking no\" $user$ssh_server$port unison -version";
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
  my $self = shift;
  my $share = shift;
  my $progress_cb = shift;
  my $first_time = shift;
  
  if (not(defined($first_time))) { $first_time = 0; }
  
  my $ignore_archives = "";
  if ($first_time) {
    $ignore_archives = "-ignorearchives";
  }

  my $args = "$ignore_archives -batch -log -dumbtty default.prf";
  my $cmd = $self->unison_cmd($share, "text", $args);
  $progress_cb->($share, "starting", -1);
  
  open my $fh, "$cmd 2>&1 |";
  while (my $line=<$fh>) {
    log_info($line);
    $progress_cb->($share, "running", -1);
  }
  close $fh;
  my $exit_code = $?;
  
  if ($exit_code == 0) {
    log_info("exitcode: $exit_code");
  } else {
    log_error("exitcode: $exit_code");
  }
  $progress_cb->($share, "done", $exit_code);
  
  return $exit_code;
}

sub run_gui() {
  my $self = shift;
  my $share = shift;
  my $args = "default.prf";
  
  my $cmd = $self->unison_cmd($share, "graphic", $args);
  
  open my $fh, "$cmd 2>&1 |";
  while (my $line=<$fh>) {
    log_info($line);
  }
  close $fh;
  my $exit_code = $?;
  
  if ($exit_code == 0) {
    log_info("exitcode: $exit_code");
  } else {
    log_error("exitcode: $exit_code");
  }
  
  return $exit_code;
}

sub server_version() {
  my $self = shift;
  my $prf = $self->profile_file();
  if (-r $prf) {
    return $self->version
  }
}

sub unison_cmd() {
  my $self = shift;
  my $share = shift;
  my $ui = shift;
  my $cmd = shift;

  my $unison = "unison-gtk";
  if ($^O eq "darwin") { $unison = "unison"; }

  my $cmd = "UNISON='".unison_dir($share)."' $unison -ui $ui $cmd";
  log_info("Unison: $cmd");
  return $cmd;
}


1;
=pod
=head1 Unison

=head2 Introduction

This package controls a unison executable and a unison configuration file.
It does this and only this. 

=end


