#!/usr/bin/perl
use v5.10;
use English;

my @directories = ( "/var/lib/transmission-daemon/downloads/", "/mnt/Public/Films/", "/mnt/Public/TV Shows" );

my @testdir = ( "/home/monty/Nature/habitat/crons/", "/home/monty/Nature/habitat/crons/test/" );

# Collect names of all test files
my @downloads = glob('/var/lib/transmission-daemon/downloads/');

my @test = glob('/home/monty/Nature/habitat/crons/*');

# Check test files for "fail"
foreach my $folder ( @test ) {
	if (grep { /^Q"s"[0-9]{2}e[0-9]{5}/ } $folder) {

  		say ("TV");
	}
	else {
		say ("Film");
	}
}



if 
