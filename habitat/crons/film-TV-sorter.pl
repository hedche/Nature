#!/usr/bin/perl
use v5.10;
use English;

my @directories = ( "/var/lib/transmission-daemon/downloads/", "/mnt/Public/Films/", "/mnt/Public/TV Shows" );

my @testdir = ( "/home/monty/Nature/habitat/crons/", "/home/monty/Nature/habitat/crons/test/" );

# Collect names of all test files
my @downloads = glob('/var/lib/transmission-daemon/downloads/');



if 
