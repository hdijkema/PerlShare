#!/usr/bin/perl
use strict;
use Expect;
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

my $exp = new Expect();
my $remote_dir = "/home/perlshare/$user/$share";

if (defined($public_keyfile)) {
  $exp->spawn("cat $public_keyfile | ".
               "ssh -o 'StrictHostKeyChecking no' ".
                   "-o 'ProxyCommand proxytunnel -q -p $host:80 -d localhost:22 -H \"$user_agent\"' ".
                   "-o 'ProtocolKeepAlives 5' ".
                   "-l $user $host ".
                   "\"cat >>.ssh/authorized_keys2;echo 'OKOKOK'\""
                );
} else {
  $exp->spawn(
               "ssh -o 'StrictHostKeyChecking no' ".
                   "-o 'ProxyCommand proxytunnel -q -p $host:80 -d localhost:22 -H \"$user_agent\"' ".
                   "-o 'ProtocolKeepAlives 5' ".
                   "-l $user $host ".
                   "\"mkdir -p $remote_dir;chmod 775 $remote_dir;echo -10 >$remote_dir/.count;echo 'OKOKOK'\""
                );
}

my $index = $exp->expect(3, "password:", "OKOKOK");

if (defined($index)) {
  if ($index == 1) {
    $exp->send("$pass\n");
    $index = $exp->expect(3, "OKOKOK");
    if (defined($index)) {
      # do nothing
    } else {
      exit 2;  # Password not accepted
    }
  } else {
    # do nothing
  }
} else {
  exit 1;   # Not even a connection possible
}

$exp->soft_close();

exit 0;

