#!/usr/bin/perl
use strict;
#use Expect;
#use IPC::Run qw( start pump finish timeout );
use PerlShareCommon::Dirs;
use PerlShareCommon::Constants;

#
# Connect using Expect to the host we want
# Exit codes determine what has happened
#
my $share = shift @ARGV or die usage();
my $host = shift @ARGV or die usage();
my $user = shift @ARGV or die usage();
my $pass = shift @ARGV or die usage();
my $public_keyfile = shift @ARGV;

my $user_agent = user_agent(); 

# Try to login to the host (using proxytunnel)
# And send over the public key file, if public_keyfile has been given

my $os = $^O;
my $keepalives = ($os=~/^MSWin/) ? "-o 'ProtocolKeepAlives 5'" : "";
my $cat = ($os=~/^MSWin/) ? "type" : "cat";
my $remote_dir = "/home/perlshare/$user/$share";

#my ($in, $out, $err, $exp);
#my $in;
#my $out;
#my $err;
#my $exp;
#my @c = ("ssh","-f","-l","hans\@oesterolt.net", "iconnect","echo OK");
#$exp = start(\@c, \$in, \$out, \$err, timeout(3));
#pump $exp until $out =~ /password|OK/;
#print "$out";
#exit 0;
if (defined($public_keyfile)) {
  my $cmd = "$cat $public_keyfile | ".
               "ssh -o 'StrictHostKeyChecking no' ".
                   "-o 'ProxyCommand proxytunnel -q -p $host:80 -d localhost:22 -H \"$user_agent\"' ".
                   "$keepalives ".
                   "-l $user $host ".
                   "\"cat >>.ssh/authorized_keys2;echo 'OKOKOK'\"";
} else {
  my $cmd =  "ssh -o 'StrictHostKeyChecking no' ".
                 "-o 'ProxyCommand proxytunnel -q -p $host:80 -d localhost:22 -H \"$user_agent\"' ".
                 "-o 'ProtocolKeepAlives 5' ".
                 "-l $user $host ".
                 "\"mkdir -p $remote_dir;chmod 775 $remote_dir;echo -10 >$remote_dir/.count;echo 'OKOKOK'\"";
               
  open my $fh, "sshpass -p $pass $cmd |";
  while (my $line = <$fh>) {
    print $line;
  }
  close($fh);
  exit(0);
               

  # my @cmd = ("ssh", "-o","StrictHostKeyChecking no",
                    # "-o","ProxyCommand proxytunnel -q -p $host:80 -d localhost:22 -H \"$user_agent\"",
                    # "$keepalives",
                    # "-l","$user",
                    # "$host",
                    # "mkdir -p $remote_dir;chmod 775 $remote_dir;echo -10 >$remote_dir/.count;echo 'OKOKOK'"
            # );
  # $exp = start( \@cmd, \$in, \$out, \$err, timeout(3) );
}

# pump $exp until $out =~ /(password:|OKOKOK)/ || $err =~/(password:|OKOKOK)/;
# if ($1 eq "") {
  # if ($1 eq "password:") {
    # $in .= "$pass\n";
    # pump $exp until $out =~ /(OKOKOK)/;
    # if ($1 eq "OKOKOK") {
      # # ok
    # } else {
      # finish($exp);
      # exit 2; # password not accepted
    # }
  # } else {
    # # ok
  # }
# } else {  
  # finish($exp);
  # exit 1;  # not even connected
# }
# 
# finish($exp);
exit 0;

# my $exp = new Expect();
# my $remote_dir = "/home/perlshare/$user/$share";
# 
# if (defined($public_keyfile)) {
  # $exp->spawn("cat $public_keyfile | ".
               # "ssh -o 'StrictHostKeyChecking no' ".
                   # "-o 'ProxyCommand proxytunnel -q -p $host:80 -d localhost:22 -H \"$user_agent\"' ".
                   # "-o 'ProtocolKeepAlives 5' ".
                   # "-l $user $host ".
                   # "\"cat >>.ssh/authorized_keys2;echo 'OKOKOK'\""
                # );
# } else {
  # $exp->spawn(
               # "ssh -o 'StrictHostKeyChecking no' ".
                   # "-o 'ProxyCommand proxytunnel -q -p $host:80 -d localhost:22 -H \"$user_agent\"' ".
                   # "-o 'ProtocolKeepAlives 5' ".
                   # "-l $user $host ".
                   # "\"mkdir -p $remote_dir;chmod 775 $remote_dir;echo -10 >$remote_dir/.count;echo 'OKOKOK'\""
                # );
# }
# 
# my $index = $exp->expect(3, "password:", "OKOKOK");
# 
# if (defined($index)) {
  # if ($index == 1) {
    # $exp->send("$pass\n");
    # $index = $exp->expect(3, "OKOKOK");
    # if (defined($index)) {
      # # do nothing
    # } else {
      # exit 2;  # Password not accepted
    # }
  # } else {
    # # do nothing
  # }
# } else {
  # exit 1;   # Not even a connection possible
# }
# 
# $exp->soft_close();

exit 0;

sub usage() {
  print "$0 share host user pass [public keyfile]\n";
  exit 3;
}
