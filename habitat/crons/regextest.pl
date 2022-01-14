#!/usr/bin/perl

use v5.10;

@array = ( "s01e05", "Film1", "S03e30", "Yes");

foreach my $item (@array) {

	#Regex with case insensitivity m/<pattern>/i
	if ($item =~ m/[sS][0-9]{2}[eE][0-9]{2}/i ){
	
		say("YEs");
	}
	else {
		say("No");
	}

}	
