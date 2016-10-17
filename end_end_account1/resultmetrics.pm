#!/charter/apps/brm50/T3R1/nonCRM/BRM/Base/ThirdParty/perl/5.8.0/bin/perl

# package to parse result/testcase.info files and generate test metrics
# 

# Revision History:
# 1/23/02: clark: initial creation
$revision = "6.3-02     11/26/02"; # clark: change output test doc tags to match OFFICIAL spec
$revision = "6.3-03     11/27/02"; # clark: always print $testdir/$pinfile::$testcase for testcase into 
$revision = "6.3-04     12/11/02"; # clark: use hash (tcm_tree) not regex for checking for pindiff new files
				   # clark: discard trash after TCASEEND, until TCASESTART
$revision = "6.*-05     2/10/04";  # clark: add CSV support


package resultmetrics;

%tcm_tree = ();		# structured version of tcasemap
@tcasemap = ();		# container for the contents of the .tcasemap file
$resultpath = "";	# container for the result directory
$tcm_index = 0;		# @tcasemap index. Saves state across array access
$TCASESTART = -1;	# state storage for most recent TCASESTART record
$TCASEDESC = -1;	# state storage for most recent DESC record
### $TCIDX = 2;		# field index of TestCaseId in TCASESTART and TCASEEND records
%TCState = (); 		# TestCase State indexed by "$pinfile $testcase"
			# $TCState->{"$pinfile $testcaseid"}
			#		{"cmd"} = [$pcmd]				# pinata commands for this case
			#		{"outfile"} = [[outfile, $state]]		# array of (outfile, state)
			#		{"state"} = $state				# total state for test case
			#		{"testdir"} = $current_pindir;
### %TCStateTotal = ();	# cumulative state of the test case
### %TCPinSteps = ();	# testcase pinata steps indexed by testcaseid
### $TCDoc = {};	# testcase documentation
###			# $TCDOC->{$pinfile}{$testcaseid}{
###                        #       "TAREA" => "testarea: short description",
###                        #       "TDESC"  => [multiline description],
###                        #       "TVERI" => [multiline verification info] }
$docpath = "";		# if present for doc print, print directly from pinfile rather than .tcasemap file


use hashfile;

# Global Variable Init


# Start the main, if running it directly
#
## resultmetrics_main() if ($0 =~ /.*resultmetrics.*/);

#
# Self-Test main
#
sub resultmetrics_main {
	   if ($ARGV[0] =~ /-h/) { 
		print "usage: $0 [flags] resultdir \n"; 
		print "\tflags\t-doc [pinfile]\t print Test Case Doc (optionally: direct from pinfile)\n";
		print "********** debug only *****************\n";
		print "\tTBD: flags\t-cm\t print Test Case Metrics\n";
		print "\tTBD: flags\t-sm\t print Test Step Metrics\n";
		print "\tTBD: flags\t-t\t print CaseList\n";
		print "\tTBD: flags\t-s\t print CaseList Summary\n";
		print "\tTBD: flags\t-l\t print State list by outfile\n";
		shift @ARGV ; 
		exit; 
		}

	while ($ARGV[0] =~ /^-/) {
		$flag = shift @ARGV;
		if ($flag =~ /-doc/) { $DocDump = 1; 		# print Test Case Document
			# get optional pin file to use
			if ($ARGV[0] =~ /^[^-]/) { $freshpin = shift @ARGV if $ARGV[0] =~ /\.pin$/; }	
			}
		elsif ($flag =~ /-cm/) { $CaseM = 1; }		# print Test Case metrics
		elsif ($flag =~ /-cs/) { $CaseS = 1; }		# print Test Case status (one case)
		elsif ($flag =~ /-sm/) { $StepM = 1; }		# print Test Step metrics
		elsif ($flag =~ /-t/) { $CaseList = 1; }		# print CaseList
		elsif ($flag =~ /-s/) { $CaseListTotal = 1; }	# print CaseList Summary
		elsif ($flag =~ /-l/) { $SList = 1; }		# print State list by outfile
		}
	$resultpath = shift @ARGV;
	if (! defined $resultpath) { $resultpath = "results"; }

	($name = $0) =~ s|^.*[\/\\]([^\/\\]*)$|$1|;
	print "$name: for $resultpath\n";	# print "resultmetrics for results"


	# print it all out
	#
	
	printDocDump($docpath, ("printall")) if $DocDump;
	printCaseMetrics() if $CaseM;
	printCaseStatus() if $CaseS;
	printStepMetrics() if $StepM;
	printCaseList("list,doc,total") if $CaseList;
	printCaseList("Total") if $CaseListTotal;
	printStepList() if $SList;

} # main

# #############################################################################
# Subroutines
# #############################################################################

# #############################################################################
# fetch_tcasemap($resultpath)
# Go get the .tcasemap info
#
# Global Variables
#
# @tcasemap = array of .tcasemap records 
# $resultpath = path to result dir
# 
# #############################################################################
sub fetch_tcasemap {
	($resultpath) = @_;
	open TCM, "$resultpath/.tcasemap" or warn "fetch_tcasemap file($resultpath/.tcasemap) ERROR $!\n";
	@tcasemap = <TCM>;
	close TCM;
	
	pinsteps();	# initialize the pinata command info as well
} # fetch_tcasemap

# #############################################################################
# ($pinfile, $testcaseid, $tcdesc) = tcasemap($resultfile, outfile)
#
# Description
#
# given an outfile, this routine looks in @tcasemap and determines the
# pinfile::testcaseid the file belongs to and its description.
#
# If it belongs to none of the testcases, it is marked as belonging to "DefaultCase"
#
# Global Variables
#
# @tcasemap  = array of .tcasemap file records
# $tcm_index = array index into @tcasemap - on the assumption that finding from current
# 		location is faster because these things will be in order
#
# #############################################################################
sub tcasemap {
	local($resultpath, $outfile) = @_;
	local($pinfile, $tcaseid);

	
	if (! defined @tcasemap) { fetch_tcasemap($resultpath); set_tcm_tree(); }
	### # set up hash of all dirdiff records to date
	### %dirdiffstat = map { $_ =~ /^DIRDIFF(.*)/?: ($1, 1); ("",0) } @tcasemap;	

	# $temp = join (" ", stat "$resultpath/". $outfile);
	@stat =  stat "$resultpath/". $outfile;
	$temp = "sz:$stat[7] mt:$stat[9] ct:$stat[10] bs:$stat[11] bk:$stat[12]";

	return ($pinfile, "DefaultCase", "") if ! exists $tcm_tree->{$outfile}{$temp};

	$pinfile = $tcm_tree->{$outfile}{$temp}{"pinfile"};
	$tcaseid = $tcm_tree->{$outfile}{$temp}{"tcaseid"};
	$tcdesc = $tcm_tree->{$outfile}{$temp}{"tcdesc"};

	return ($pinfile, $tcaseid, $tcdesc);

	### for $idx ($tcm_index..$#tcasemap,0..$tcm_index) {
	### 	$TCASESTART = $idx if $tcasemap[$idx] =~ /TCASESTART/;
	### 	$TCASEDESC = $idx if $tcasemap[$idx] =~ /DESC/;
	### 	if ($tcasemap[$idx] =~ /\/$outfile\/ $temp/) { 	# found the record
	### 	### if ($dirdiffstat{"\/$outfile\/ $temp/"}/) { 	# found the record
	### 		($current_pindir = (split " ", $tcasemap[$TCASESTART])[1]) =~ s|/||g;
	### 		($pinfile = (split " ", $tcasemap[$TCASESTART])[2]) =~ s|/||g;
	### 		($tcaseid = (split " ", $tcasemap[$TCASESTART])[3]) =~ s|/||g;
	### 		$tcdesc = (split " ", $tcasemap[$TCASEDESC], 4)[3];
	### 		$tcm_index = $idx;
	### 		return ($pinfile, $tcaseid, $tcdesc);
	### 		}
	### 	}

	### return ($pinfile, "DefaultCase", "");

} # tcasemap

# #####################################################################################
# set_tcm_tree
#
#	$tcm_tree->{$file}{$stat}{"pinfile"} = $pinfile;
#	$tcm_tree->{$file}{$stat}{"tcaseid"} = $tcaseid;
#	$tcm_tree->{$file}{$stat}{"tcdesc"} = $tcdesc;
# 
# #####################################################################################
sub set_tcm_tree {
my ($current_pindir) = "";
my ($pinfile) = "";
my ($tcaseid) = "";
my ($tdiff_line) = "";
my ($trash) = 1;	 # All is trash until you hit "TCASESTART" !!!!
my ($tctime) = "";

foreach my $line (@tcasemap) {
	chomp $line;
	if ( $line =~ /^TCASESTART/ ) { 
		$trash = 0;	# resume processing entries for this new test case
		$tcs_line = $line; 

		($current_pindir = (split " ", $line)[1]) =~ s|/||g;
                ($pinfile = (split " ", $line)[2]) =~ s|/||g;
                ($tcaseid = (split " ", $line)[3]) =~ s|/||g;
		$tcdesc = "";
		}
	elsif ( $line =~ /TCASEEND/ ) {
		$trash = 1;	# Anything after this is "the next cases pre-initial condition" TOSS IT
		}
	elsif ( $trash ) { next; }

	elsif ( $line =~ /^DESC/ )    { 
                $tcdesc = (split " ", $line, 4)[3];
		}
	elsif ( $line =~ /^PINCMD/ ) { 
                # ($current_pindir = (split " ", $line)[1]) =~ s|/||g;
                # ($pinfile = (split " ", $line)[2]) =~ s|/||g;
                # ($tcaseid = (split " ", $line)[3]) =~ s|/||g;
		# $line =~ /\/\s+\(([^)]*)\)/;
		# $tctime = $1;
		}
	elsif ( $line =~ /^DIRDIFF/ ) { 
		### ($tdiff_line = $line) =~ s/^DIRDIFF\s*//;
		my ($null, $file, $stat) = split("/", $line, 3);
		$stat =~ s/^\s*//;

		$tcm_tree->{$file}{$stat}{"pinfile"} = $pinfile;
		$tcm_tree->{$file}{$stat}{"tcaseid"} = $tcaseid;
		$tcm_tree->{$file}{$stat}{"tcdesc"} = $tcdesc;
		}
	else { }
	} 

}

# ################################################################################
# printDocDump
#
# Description: Prints testcase info
# Standards for output for Apthi readability:
#
# The Fields are:
# FIELD NAME		contents		meaning
#
#	TCASE	$testdir/$pinfile::$tcase	# Test Case ID
# 	TAREA		$info			# Test Case Area
# 	TDESC		$info			# Test Case Description
#	TVERI		$info			# Test Case Verification
#	TACOS		$info			# Test Case Associated Change Orders
#	TAUTO		$info			# Test Case Automation Status
#	TCOMM		$info			# Test Case Comment 
#	TMDBY		$info			# Test Case Modifed By owner
#	TMDDA		$info			# Test Case Modify Date
# 	TPRIO		$info			# Test Case Priority
#	TSUIT		$info			# Test Case Regression Suite 
#
# NOTE: New fields must follow these rules:
#
#	1) Start with an initial capital "T"
#	2) Followed by 4 capital letters
#	3) Followed by any additional capital letters
#	4) Followed by a ":" and a space " ".
#	5) command specific data follows the white space
#
#	leading white space is ignored
#	trailing white space is ignored
#	internal white space is converted to single spaces
#	multi-line data is seperated by ";;" in the apthi csv output
#	all control chars are stripped
#	double quotes are converted to single quotes
#
# ################################################################################
sub printDocDump {
	my ($docpath, @printall) = @_;	# if $fresh, print direct from pinata, else use results*/.tcasemap

	my ($cmd, $info, $pinfile, $tcase);
	### my %printed = {};

	if (-f $docpath) {	# ITS A FILE, so treat it like a pinata file
		@tcasemap = `pinata -doc $docpath`;
		if ($#tcasemap < 0) { 
			print "ERROR: can not fetch Test Case docs from $docpath\n";
			system ("pinata -doc $docpath >junk"); 	# This prints the error the sh gets
			}
		}
	elsif (! defined @tcasemap) { 
		fetch_tcasemap($docpath) 
		}

	for $idx (0..$#tcasemap) {

		# sample error: Command ERROR. Unknown command (.testdescription <text>)
		if ($tcasemap[$idx] =~  /^ERROR/) {print $tcasemap[$idx], "\n"; next; }

		# sample line: TAREA /testdir pinfile testcase/ description
		# sample line: TDESC /testdir pinfile testcase/ description
		# sample line: TDESC more description
		# sample line: TDESC more description
		#
		if ($tcasemap[$idx] =~ /\s+\/|\/\s+|\/$/) {
			($cmd, $tcase, $info) = split (/\s+\/|\/\s+|\/$/, $tcasemap[$idx], 3);
			($testdir, $pinfile, $tcase) = split (/\s+/, $tcase);
			}
		else {
			# $testdir, $pinfile, $tcase hang around from the last time they were set
			($cmd, $info) = split (/\s+/, $tcasemap[$idx], 2);
			}

		### exit if ($printed{$tcase});
		### $printed{$tcase} = 1;

		$printlist = join "|", @printall;
		if ($printall[0] =~ /all/i) { }		# print everything
		elsif (! $printall[0]) {} 			# print every entry, only the testcase info
		elsif ($tcase =~ /$printlist/i) { } 	# print everything, only for each testcase mentioned
		else 	{ next; }			# don't print this testcase

		### if ($cmd =~ /(TCASESTART|TAREA|TDESC|TVERI|TEND)/) { } else { next; }

		if ($cmd =~ /TCASESTART/) { 
			}
		elsif ($cmd =~ /TAREA/) { 
			if ($printall[0]) {
				if (! $testdir ) { print "ERROR: Test Directory not defined for: $cmd $info\n"; }
				if (! $pinfile ) { print "ERROR: Pinata File not defined for: $cmd $info\n"; }
				if (! $tcase ) { print "ERROR: Test Case not defined for: $cmd $info\n"; }
				#### print "\nTCASE: $testdir $pinfile/$tcase\n";
				print '-' x 80, "\n";
				print "TCASE: $testdir/$pinfile", "::", "$tcase\n";
				if ($info) { print "TAREA: $info"; }
				}
			else { # print only short info 
				($name = $0) =~ s|^.*[\/\\]([^\/\\]*)$|$1|;
				print "TestCaseDir=$testdir/$docpath\n" if "$testdir/$docpath" ne $oldrespath ;
				print "pinfile=$pinfile\n" if $pinfile ne $oldpinfile;
				print "($tcase): $info";

				$oldrespath = "$testdir/$docpath";
				$oldpinfile = $pinfile;
				}
			}

		### elsif ($cmd =~ /TDESC/ && $printall[0]) {  
		### 	if ($info) { print "TDESC: $info"; }
		### 	}

		### elsif ($cmd =~ /TVERI/ && $printall[0]) { 
		### 	if ($info) { print "TVERI: $info"; }
		### 	}

		elsif ($cmd =~ /(TDESC|TVERI|TACOS|TAUTO|TCOMM|TMDBY|TMDDA|TPRIO|TSUIT)/ && $printall[0]) {
			if ($info) { print "$1: $info"; }
			}
	
		$prev = $cmd;
		}
} # printDocDump

sub pinsteps {
	for $idx (0..$#tcasemap) {
		if ($tcasemap[$idx] =~ /TCASESTART/) {
			$TCASESTART = $idx;
			### $current_pindir = (split " ", $tcasemap[$TCASESTART])[1];
			$current_pindir = (split " ", $tcasemap[$idx])[1];
			### $pinfile = (split " ", $tcasemap[$TCASESTART])[2];
			$pinfile = (split " ", $tcasemap[$idx])[2];
			$tcaseid = (split " ", $tcasemap[$idx])[3];
			$current_pindir =~ s|/||g;
			$pinfile =~ s|/||g;
			$tcaseid =~ s|/||g;
			}
		if ($tcasemap[$idx] =~ /PINCMD/) {
			$case = $pinfile. "__". $tcaseid;
			$pcmd = (split " ", $tcasemap[$idx], 5)[4];
			push @{$TCState->{$case}{"cmd"}}, "$pcmd";
			$TCState->{$case}{"testdir"} = $current_pindir;
			}
                ### if ($tcasemap[$idx] =~ /DIRDIFF/) {
                ###         $case = $pinfile. "__". $tcaseid;
                ###         $outfile = (split " ", $tcasemap[$idx], 2)[1];
		###         $outfile =~ s|/||;
                ###         push @{$TCState{$case}{"outfile"}}, $outfile;
                ###         }
		}
} # pinsteps

# #############################################################################
# settcasestate ($pinfile, $tcaseid, $outfile, $state)
#
# Description
#
# TCState->{"$pinfile__$testcaseid"}{"outfile"} = [$testoutfile, $state]
# 						{$state} = $state
# 
# #############################################################################
sub settcasestate {
	local($pinfile, $tcaseid, $outfile, $state) = @_;
	local ($case) = $pinfile. "__". $tcaseid;
	push @{$TCState->{$case}{"outfile"}}, [$outfile, $state];
	$TCState->{$case}{"state"} = StateAdd ($TCState->{$case}{"state"}, $state);
	$TCState->{$case}{"testdir"} = $current_pindir;
} # tcasestate

# #############################################################################
# StateAdd ($state1, $state2)
# Pass + Pass = Pass
# Pass + Warn = Warn
# Pass + Fail = Fail
# Warn + Fail = Fail
# Fail + Fail = Fail
# * + NotRun = NOTRUN
# "" + "" = Unknown
# #############################################################################
sub StateAdd {
	my ($state1, $state2) = @_;
	$state1 = uc $state1;
	$state2 = uc $state2;

	my $states = ",$state1,$state2,";		# glue them all into one
	return "NotRun" if $states =~ /,NOTRUN,/ ;
	return "Fail" if $states =~ /,FAIL,/ ;
	return "Pass" if $states =~ /,WARN,/ ;
	return "Pass" if $states =~ /,PASS,/ ;
	return "Unknown";	# give up and return SOMETHING!

} # StateAdd

# #############################################################################
# printCaseList ($tflag)
# where tflag is a string containing one or more of
#	list, total, doc
#
# TestCase result: pinfile::testcase   Status
# TestCase result: pinfile::testcase   Status
# ...
# 
# w/ $tflag
#
# TestCase Result Overall: Status (e.g. Pass)
#
# $tflag true => only print the summary total of all cases together
#        false => print the status of each test case
# 
# #############################################################################
sub printCaseList {
	local ($tflag) = @_;	# flag string: "list", "total", "doc"

	local ($clflag) = ($tflag =~ /list/i);
	local ($totalflag) = ($tflag =~ /total/i);
	local ($docflag) = ($tflag =~ /doc/i);

	# case = $pinfile__$testcaseid
        ### print " " x 13, "Test\t\tTestCase \tPass/Fail\n" if $clflag;
	### print " " x 13, "----\t\t---------\t---------\n" if $clflag;
	foreach $case (sort keys %{$TCState}) {
		($printcase = $case) =~ s|__|::|;
		local($testdir) = $TCState->{$case}{"testdir"};

		$butnotdefault = ! ($case =~ /__defaultcase/i);
		print '-' x 80, "\n" if ($docflag and $clflag and $butnotdefault);

		print "CASE=$testdir/$printcase", "\tResult=$TCState->{$case}{'state'}", "\n" if $clflag; 
		local ($pinfile, $tcase) = split /__/, $case;
		printDocDump("", ("$tcase")) if $docflag;

		$ttotal = StateAdd($ttotal, $TCState->{$case}{"state"});
		}
	print '-' x 80, "\n" if $totalflag and ($cflag or $docflag);
	print "TestCaseResultTotal=$ttotal\n" if $totalflag;
} # printCaseList

sub printCSV {
	# Generate a comment header
	@CSVKeys = ("build", "platform", "run_date", "directory", "caseid", "status");
	print "# ", join(", ", @CSVkeys), "\n";
	local($build) = "6.7_sample";
	local @BASEData = ("6.7_FP2_020504", "hpux", "02/05/04", "ALAR");

	foreach $case (sort keys %{$TCState}) {
		$caseid = $case;
		local(@CSVdata) = push @CSVdata, $case;
		push @CSVdata, $TCState->{$case}{'state'};
		print join(", ", @CSVdata), "\n";
		}
} # printCSV

sub printTestStatus {
	printCaseList("total");
} # printTestStatus
# #############################################################################
# printStepList
#
# prints one line per test case:
# pinfile/TestCase 	Status
# 	outfile: filename	Status
# =================== totalState ===============   
# #############################################################################
sub printStepList {
	local ($wcmds) = @_;
	local ($totalState, $state, $cmd);

	## print "Test\t\tTest Case\t\t\tstatus\n";
	## print "----\t\t---------\t\t\t------\n";
	foreach $case (sort keys %{$TCState}) {
		($print_case = $case) =~ s|__|::|;
		local($testdir) = $TCState->{$case}{"testdir"};
		print "$testdir/$print_case \tResult=$TCState->{$case}{'state'}\n";
		$totalState = "";	# reset the cumulative state

		if ($wcmds) {
		   print "\t*** pinata commands ($case)\n" if $debug;
		   foreach $cmd (@{$TCState->{$case}{"cmd"}}) {
			print "\t$cmd";
			}
		   print "\t", '-' x 40, "\n";
		   }
 
		print "\t*** status by output file ($case)\n" if $debug;
		foreach $outfile (@{$TCState->{$case}{"outfile"}}) {
			print "\tOutFile=@$outfile[0] \tResult=$$outfile[1]\n";
			$totalState = StateAdd($totalState, $$outfile[1]);
		   	}
		print "\tTotalResult=$totalState\n";
		print "-" x 80, "\n";
		}
} # printStepList

# #############################################################################
# printCaseMetrics
# prints  TCState->{"$pinfile__$testcaseid"}{"state"} = $state
#
# prints 1 line:
# #Cases=NN   #Pass=NN   #Fail=NN   #Unknown=NN
#
# #############################################################################
sub printCaseMetrics {
	### print "Total Test Case Metrics\n";
	local ($F, $P, $N, $T) = (0, 0, 0, 0);
	foreach $case (sort keys %{$TCState}) {
		$F++ if $TCState->{$case}{"state"} =~ /Fail/;
		$P++ if $TCState->{$case}{"state"} =~ /Pass/;
		$P++ if $TCState->{$case}{"state"} =~ /Warn/;	# Warnings count as Pass
		$W++ if $TCState->{$case}{"state"} =~ /Warn/;	# Advisory only
		$U++ if $TCState->{$case}{"state"} =~ /Unknown/;
		$N++ if $TCState->{$case}{"state"} =~ /NotRun/;
		$T++;
		}
	### print "#Cases   #Pass     #Fail     #NotRun\n";
	print "#Cases=$T", "\t", "#Pass=$P", "\t", "#Fail=$F", "\t", "#Unknown=$U", "\t", 
		# "(Warn=$W)", 	# not currently in favor - pull it out
		# "(NotRun=$N)", 	# not currently in favor - pull it out
		"\n"; 

} # printCaseMetrics

# #############################################################################
# printStepMetrics
# TCState->{"$pinfile__$testcaseid}{"outfile"}=[[$testoutfile, $state], [$testoutfile, $state]]
#
# Total Test Step Metrics
# #PinSteps: NN	   #Outfiles: NN   #Pass: NN     #Fail: NN     #NotRun: NN     #Warn: NN
# #############################################################################
sub printStepMetrics {
	### print "Total Test Step Metrics\n";
	local ($O, $C, $P, $F, $N, $W, $PS);

	$PC=$O=$C=$P=$F=$N=$W=$PS = 0;
	foreach $case (sort keys %{$TCState}) {
		$state = $TCState->{$case}{"state"};
		$C++;
		$P++ if $state =~ /Pass/;
		$P++ if $state =~ /Warn/; # Warnings count as Pass
		$W++ if $state =~ /Warn/; # Advisory
		$F++ if $state =~ /Fail/;
		$N++ if $state =~ /NotRun/;
		$W++ if $state =~ /Warn/;
	
		$PC += 1 + $#{$TCState->{$case}{"cmd"}};
		$O += 1 + $#{$TCState->{$case}{"outfile"}}
		}

	print "#PinCmds=$PC", "\t", "#Outfiles=$O", "\t", "#TestCases=$C",
		"\t", "#Pass=$P", "\t", "#Fail=$F", "\t", 
			# "#NotRun: $N", 		# not sure what this means ... later
			# "\t", "(#Warn: $W)", 		# not currently in favor, pull it out
			"\n";

} # printStepMetrics

# #############################################################################
# printCaseStatus
#
# Description: print cumulative status for the testcase an out-file belongs to
#
# TestCase: <testcaseid> <status>
#	where: <status> = Pass | Fail | NotRun
# #############################################################################
sub printCaseStatus {
	($pinfile, $testcaseid, $outfile) = @_;
	$case = $pinfile. "__". $testcaseid;
	local $status = $TCState->{$case}{"state"};
	local $testdir = $TCState->{$case}{"testdir"};
	### print "TestCase outfile Result: $pinfile/$testcaseid $status for $outfile\n";
	print "CASE=$testdir/$pinfile", "::", "$testcaseid", " \t", "Result=$status", " \t", "File=$outfile\n";
} # printCaseStatus

1;
