#!/usr/bin/perl -w
#Auther: zlq

use strict;
use warnings;
use Getopt::Std;
	while(<>){
		next unless (m/Real/);
		my @t = split(" ");
		print $t[3]," ","\n";	
	}
exit;


