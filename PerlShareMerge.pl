#!/usr/bin/perl
# 
# Resolves a conflict for unison in a DropBox like manner
#
use strict;
use File::Copy;
use POSIX qw/strftime/;

my $sharedir = shift @ARGV or usage();
my $path = shift @ARGV or usage();
my $current_local = shift @ARGV or usage();
my $current_remote = shift @ARGV or usage();
my $new_file = shift @ARGV or usage();

#
# Always copy current_remote to new.
# because current_local can be edited
#
# We try to link, but if it doesn't work, 
# we do copy, because we want to support FAT

my $name = $path;
$name =~ s/[.][^.]+$//;
$path =~ /([.][^.]+$)/;
my $ext = $1;

my $dt = strftime("%Y-%m-%d", localtime);
my $conflicted_copy = "$sharedir/$name"."-conflicted-copy-"."$dt$ext";

print "linking local file to new\n";
if (not(link($current_local, $new_file))) {
  copy($current_local, $new_file);
}  

print "creating conflicted copy of remote file";
copy($current_remote, $conflicted_copy);

print "touching .conflict file";
open my $fh, ">$sharedir/.conflict";
close $fh;

exit 0;

sub usage() {
  print "To be used with PerlShare.pl\n";
  exit 1;
}