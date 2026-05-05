#!/usr/bin/perl

use v5.10;

@array = ( "fwfkmowmfs01e05fAEGR.MP4", "FEF1080pilm1", "GEhtebS03e30eb", "Yes");

my @dirs = glob('');

foreach my $item (@array) {

	#Regex with case insensitivity m/<pattern>/i
	if ($item =~ m/[sS][0-9]{2}[eE][0-9]{2}/i ){
	
		say("TV");
	}
	elsif ($item =~ /[0-9]{4}/) {

		say("Film");
	}
	else {
		say("N/A");
	}
}	
