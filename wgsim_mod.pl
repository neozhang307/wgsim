#!/usr/bin/perl -w

# Author: lh3

use strict;
use warnings;
use Getopt::Std;

die (qq/
Usage:   wgsim_eval.pl <command> <arguments>

Command: alneval       evaluate alignment in the SAM format
         vareval       evaluate variant calls in the pileup format
         unique        keep the top scoring hit in SAM
         uniqcmp       compare two alignments without multiple hits
\n/) if (@ARGV == 0);
my $command = shift(@ARGV);
if ($command eq 'alneval') {
	&alneval;
} elsif ($command eq 'vareval') {
	&vareval;
} elsif ($command eq 'unique') {
	&unique;
} elsif ($command eq 'uniqcmp') {
	&uniqcmp;
} else {
	die("[wgsim_eval] unrecognized command.\n");
}
exit;

sub alneval {
	my %opts = (g=>20);
	getopts('pag:', \%opts);
	die(qq/
Usage:   wgsim_eval.pl alneval [options] <in.sam>\n
Options: -p        print wrong alignments
         -g INT    correct if withint INT of the true coordinate
\n/) if (@ARGV == 0 && -t STDIN);
	my (@c0, @c1, %fnfp);
	my ($max_q, $flag) = (0, 0);
	my $gap = $opts{g};
	$flag |= 1 if (defined $opts{p});
	while (<>) {
		next if (/^\@/);
		my @t = split("\t");
		next if (@t < 11);
		my $line = $_;
		my ($q, $is_correct, $chr, $left, $rght) = (int($t[4]/10), 1, $t[2], $t[3], $t[3]);
		$max_q = $q if ($q > $max_q);
		# right coordinate
		$_ = $t[5]; s/(\d+)[MDN]/$rght+=$1,'x'/eg;
		--$rght;
		# correct for clipping
		my ($left0, $rght0) = ($left, $rght);
		$left -= $1 if (/^(\d+)[SH]/);
		$rght += $1 if (/(\d+)[SH]$/);
		$left0 -= $1 if (/(\d+)[SH]$/);
		$rght0 += $1 if (/^(\d+)[SH]/);
		# skip unmapped reads
		next if (($t[1]&0x4) || $chr eq '*');
		# parse read name and check
		if ($t[0] =~ /^(\S+)_(\d+)_(\d+)_/) {
			if ($1 ne $chr) { # different chr
				$is_correct = 0;
			} else {
				if ($t[1] & 0x10) { # reverse
					$is_correct = 0 if (abs($3 - $rght) > $gap && abs($3 - $rght0) > $gap); # in case of indels that are close to the end of a reads
				} else {
					$is_correct = 0 if (abs($2 - $left) > $gap && abs($2 - $left0) > $gap);
				}
			}
		} else {
			warn("[wgsim_eval] read '$t[0]' was not generated by wgsim?\n");
			next;
		}
		++$c0[$q];
		++$c1[$q] unless ($is_correct);
		@{$fnfp{$t[4]}} = (0, 0) unless (defined $fnfp{$t[4]});
		++$fnfp{$t[4]}[0];
		++$fnfp{$t[4]}[1] unless ($is_correct);
		print STDERR $line if (($flag&1) && !$is_correct && $q > 0);
	}
	# print
	my ($cc0, $cc1) = (0, 0);
	if (!defined($opts{a})) {
		for (my $i = $max_q; $i >= 0; --$i) {
			$c0[$i] = 0 unless (defined $c0[$i]);
			$c1[$i] = 0 unless (defined $c1[$i]);
			$cc0 += $c0[$i]; $cc1 += $c1[$i];
			printf("%.2dx %12d / %-12d  %12d  %.3e\n", $i, $c1[$i], $c0[$i], $cc0, $cc1/$cc0) if ($cc0);
		}
	} else {
		for (reverse(sort {$a<=>$b} (keys %fnfp))) {
			next if ($_ == 0);
			$cc0 += $fnfp{$_}[0];
			$cc1 += $fnfp{$_}[1];
			print join("\t", $_, $cc0, $cc1), "\n";
		}
	}
}

sub vareval {
	my %opts = (g=>10, Q=>200);
	getopts('g:p', \%opts);
	my $skip = $opts{g};
	die("Usage: wgsim_eval.pl vareval [-g $opts{g}] <wgsim.snp> <pileup.flt>\n") if (@ARGV < 1);

	my $is_print = defined($opts{p})? 1 : 0;

	my ($fh, %snp, %indel);
	# read simulated variants
	open($fh, $ARGV[0]) || die;
	while (<$fh>) {
		my @t = split;
		if (@t != 5 || $t[2] eq '-' || $t[3] eq '-') {
			$indel{$t[0]}{$t[1]} = 1;
		} else {
			$snp{$t[0]}{$t[1]} = $t[3];
		}
	}
	close($fh);

	shift(@ARGV);
	my (@cnt);
	for my $i (0 .. 3) {
		for my $j (0 .. $opts{Q}) {
			$cnt[$i][$j] = 0;
		}
	}
	while (<>) {
		my @t = split;
		my $q = $t[5];
		next if ($t[2] eq $t[3]);
		$q = $opts{Q} if ($q > $opts{Q});
		if ($t[2] eq '*') {
			my $hit = 0;
			++$cnt[2][$q];
			for my $i ($t[1] - $skip .. $t[1] + $skip) {
				if (defined $indel{$t[0]}{$i}) {
					$hit = 1; last;
				}
			}
			++$cnt[3][$q] if ($hit == 0);
			print STDERR $_ if ($hit == 0 && $is_print);
		} else {
			++$cnt[0][$q];
			++$cnt[1][$q] unless (defined $snp{$t[0]}{$t[1]});
			print STDERR $_ if (!defined($snp{$t[0]}{$t[1]}) && $is_print);
		}
	}

	for (my $i = $opts{Q} - 1; $i >= 0; --$i) {
		$cnt[$_][$i] += $cnt[$_][$i+1] for (0 .. 3);
	}

	for (my $i = $opts{Q}; $i >= 0; --$i) {
		print join("\t", $i, $cnt[0][$i], $cnt[1][$i], $cnt[2][$i], $cnt[3][$i]), "\n";
	}
}

sub unique {
	# -f: parameter to recalute mapping quality
	# -Q: do not recalculate mapping quality
	# -a, -b, -q, -r: scoring system
	my %opts = (f=>250.0, q=>5, r=>2, a=>1, b=>3);
	getopts('Qf:q:r:a:b:m', \%opts);
	die(qq/
Usage:   wgsim_eval.pl unique [options] <in.sam>\n
Options: -Q         recompuate mapping quality from multiple hits
         -f FLOAT   mapQ=FLOAT*(best1-best2)\/best1 [opts{f}]
         -a INT     matching score (when AS tag is absent) [$opts{a}]
         -q INT     gap open penalty [$opts{q}]
         -r INT     gap extension penalty [$opts{r}]
\n/) if (@ARGV == 0 && -t STDIN);
	my $last = '';
	my $recal_Q = defined($opts{Q});
	my $multi_only = defined($opts{m});
	my @a;
	while (<>) {
		my $score = -1;
		print $_ if (/^\@/);
		$score = $1 if (/AS:i:(\d+)/);
		my @t = split("\t");
		next if (@t < 11);
		if ($score < 0) { # AS tag is unavailable
			my $cigar = $t[5];
			my ($mm, $go, $ge) = (0, 0, 0);
			$cigar =~ s/(\d+)[ID]/++$go,$ge+=$1/eg;
			$cigar = $t[5];
			$cigar =~ s/(\d+)M/$mm+=$1/eg;
			$score = $mm * $opts{a} - $go * $opts{q} - $ge * $opts{r}; # no mismatches...
		}
		$score = 1 if ($score < 1);
		if ($t[0] ne $last) {
			&unique_aux(\@a, $opts{f}, $recal_Q, $multi_only) if (@a);
			$last = $t[0];
		}
		push(@a, [$score, \@t]);
	}
	&unique_aux(\@a, $opts{f}, $recal_Q, $multi_only) if (@a);
}

sub unique_aux {
	my ($a, $fac, $is_recal, $multi_only) = @_;
	my ($max, $max2, $max_i) = (0, 0, -1);
	for (my $i = 0; $i < @$a; ++$i) {
		if ($a->[$i][0] > $max) {
			$max2 = $max; $max = $a->[$i][0]; $max_i = $i;
		} elsif ($a->[$i][0] > $max2) {
			$max2 = $a->[$i][0];
		}
	}
	if ($is_recal) {
		if (!$multi_only || @$a > 1) {
			my $q = int($fac * ($max - $max2) / $max + .499);
			$q = 250 if ($q > 250);
			$a->[$max_i][1][4] = $q < 250? $q : 250;
		}
	}
	print join("\t", @{$a->[$max_i][1]});
	@$a = ();
}

sub uniqcmp {
  my %opts = (q=>20, s=>100, b=>4);
  getopts('pq:s:b:', \%opts);
  die(qq/
Usage:   wgsim_eval.pl uniqcmp [options] <in1.sam> <in2.sam>\n
Options: -q INT     confident mapping if mapping quality above INT [$opts{q}]
         -s INT     same mapping if the distance below INT [$opts{s}]
         -b INT     penalty for a difference [$opts{b}]
\n/) if (@ARGV < 2);
  my ($fh, %a);
  #my $repeat = 0;
  warn("[uniqcmp] read the first file...\n");
  &uniqcmp_aux($ARGV[0], \%a, 0, $opts{b});
  #warn("skip $repeat \n");
  warn("[uniqcmp] read the second file...\n");
  #$repeat=0;
  &uniqcmp_aux($ARGV[1], \%a, 1, $opts{b});
  #warn("skip $repeat \n");
  warn("[uniqcmp] stats...\n");
  my @cnt;
  $cnt[$_] = 0 for (0..9);
  my @counter;
  $counter[$_] = 0 for (0..5);
  
  for my $x (keys %a) {
        $counter[5]++;
	my $p = $a{$x};
	my $z;
	if (defined($p->[0]) && defined($p->[1])) {
	  $z = ($p->[0][0] == $p->[1][0] && $p->[0][1] eq $p->[1][1] && abs($p->[0][2] - $p->[1][2]) < $opts{s})? 0 : 1;
          $counter[$z]++;
	  if ($p->[0][3] >= $opts{q} && $p->[1][3] >= $opts{q}) {
		++$cnt[$z*3+0];
	  } elsif ($p->[0][3] >= $opts{q}) {
		++$cnt[$z*3+1];
	  } elsif ($p->[1][3] >= $opts{q}) {
		++$cnt[$z*3+2];
	  }
	  print STDERR "$x\t$p->[0][1]:$p->[0][2]\t$p->[0][3]\t$p->[0][4]\t$p->[1][1]:$p->[1][2]\t$p->[1][3]\t$p->[1][4]\t",
		$p->[0][5]-$p->[1][5], "\n" if ($z && defined($opts{p}) && ($p->[0][3] >= $opts{q} || $p->[1][3] >= $opts{q}));
	} elsif (defined($p->[0])) {
	 $counter[2]++;
	  ++$cnt[$p->[0][3]>=$opts{q}? 6 : 7];
	  print STDERR "$x\t$p->[0][1]:$p->[0][2]\t$p->[0][3]\t$p->[0][4]\t*\t0\t*\t",
		$p->[0][5], "\n" if (defined($opts{p}) && $p->[0][3] >= $opts{q});
	} else {
	  $counter[3]++;
	  print STDERR "$x\t*\t0\t*\t$p->[1][1]:$p->[1][2]\t$p->[1][3]\t$p->[1][4]\t",
		-$p->[1][5], "\n" if (defined($opts{p}) && $p->[1][3] >= $opts{q});
	  ++$cnt[$p->[1][3]>=$opts{q}? 8 : 9];
	}
  }
  print "the total size is $counter[5]\n";
  print "the match size is $counter[0]\n";
  print "the missmatch size is $counter[1]\n";
  print "the second miss is $counter[2]\n";
  print "the first miss is $counter[3]\n";
  print "Consistent (high, high):   $cnt[0]\n";
  print "Consistent (high, low ):   $cnt[1]\n";
  print "Consistent (low , high):   $cnt[2]\n";
  print "Inconsistent (high, high): $cnt[3]\n";
  print "Inconsistent (high, low ): $cnt[4]\n";
  print "Inconsistent (low , high): $cnt[5]\n";
  print "Second missing (high):     $cnt[6]\n";
  print "Second missing (low ):     $cnt[7]\n";
  print "First  missing (high):     $cnt[8]\n";
  print "First  missing (low ):     $cnt[9]\n";
}

sub uniqcmp_aux {
  my ($fn, $a, $which, $b) = @_;
  my $fh;
  $fn = "samtools view $fn |" if ($fn =~ /\.bam/);
  open($fh, $fn) || die;
  my $repeat=0;
  while (<$fh>) {
	my $score = -1;
	$score = $1 if (/AS:i:(\d+)/);
	my @t = split;
	next if (@t < 11);
#	my $l = ($t[5] =~ /^(\d+)S/)? $1 : 0;
	my $l = 0;
	my ($x, $nm) = (0, 0);
	$nm = $1 if (/NM:i:(\d+)/);
	$_ = $t[5];
	s/(\d+)[MI]/$x+=$1/eg;
	if(!$a->{$t[0]}[$which])
	{
		@{$a->{$t[0]}[$which]} = (($t[1]&0x10)? 1 : 0, $t[2], $t[3]-$l, $t[4], "$x:$nm", $x - $b * $nm, $score);
	}  
	else
	{
#		print "here";
		$repeat=$repeat+1;
		my $p = $a->{$t[0]};
		if($p->[$which][6]<$score)
		{
			@{$a->{$t[0]}[$which]} = (($t[1]&0x10)? 1 : 0, $t[2], $t[3]-$l, $t[4], "$x:$nm", $x - $b * $nm, $score);
		}
	}
  }
  warn("skip $repeat /n");
  close($fh);
}
