#!/home/pin/portal/ThirdParty/perl/5.8.0/bin/perl

package hashfile;

# package to read and write hashfiles to save variable context external to specific perl programs
# includes routines to get pin_virtual_time and system_time - works on NT and UNIX
# 

# ##################################################################################################
# Revision History
#
  $revision = '6.2-01';                # cwj: warn rather than die when write of hashfile fails
  $revision = '7.3-02';                # bertm: Added 1900 to the year to make it correct.
# ##################################################################################################



sub hashfilemain {
	($task, $hashpath) = @ARGV;

	if (! $task ) { print "usage: $0 task hashpath\n"; exit; }

	if ($task =~ /read/) {
		local %hash;
		read_hashfile ($hashpath, *hash);
	
		$idx=0;
		foreach $key (sort keys %hash) {
			print $idx++ .") $key\t=> $hash{$key}\n";
			}
	
		}
	elsif ($task =~ /write/) {
		local %hash = ("key1" => "val1",
				"key2" => "val2",
				"key3" => "val3",
				"key4" => "val4",
                        	"key5" => "val5",
                        	"key6" => "val6",
                        	"key7" => "val7",
                        	"key8" => "val8",
                        	"key9" => "val9");	

		write_hashfile ($hashpath, *hash);
	
		}
	}

# #######################################################################################
# Subroutines
# #######################################################################################
sub read_hashfile {
	local ($hash_path, *hash) = @_;
	
	%hash=();
	# Don't DIE on open error, just return an empty hash, to be filled up and written later
	open (HASH, "<$hash_path") or ( warn "Error on Read of Hashfile ($hash_path): $!\n" and return) ;
	while (<HASH>) {
		$_ =~ / *(\S+) *(.*)/;
		next if ($1 =~ / *#/);	# ignore comments
		next if ($1 =~ /^ *$/);	# ignore blank lines
		$hash{$1} = $2;
		}
	close HASH;
	} # read_hashfile

sub write_hashfile {
	local ($hash_path, *hash) = @_;
	open (HASH, ">$hash_path") or warn "Error on Write of Hashfile ($hash_path): $!\n";
	local ($dt, $date, $time);
        $dt = time ();
        ($date, $time) = &getDateTime ($dt);
	print HASH "#  $date";
	print HASH "#  (from: $0)\n\n";
	foreach $key (keys %hash) {
		print HASH "$key  $hash{$key}\n";
		}
	close HASH;
	} # write_hashfile

###############################################################################
#
# Function    : getPinTime
#
# Description : Get current Infranet time
#
###############################################################################
sub getPinTime {

    # Get current Infranet time
    #
    # If running in a view as part of a build, then add the correct suffix.
    my $pin_virtual_time = 'pin_virtual_time';
    if (exists $ENV{TEST_EXE_SUFFIX}) {
        $pin_virtual_time .= $ENV{TEST_EXE_SUFFIX};
    }
    $current_pin_time = `$pin_virtual_time`;
    local ($tmp1, $tmp2, $tmp3, $dow, $month, $day, $time, $year) = split (" ", $current_pin_time);
    local ($hour, $min, $sec) = split (":", $time);
    local ($date, $time);

    # Convert the months to digits!
    #
    $mon = "01"  if $month eq "Jan";
    $mon = "02"  if $month eq "Feb";
    $mon = "03"  if $month eq "Mar";
    $mon = "04"  if $month eq "Apr";
    $mon = "05"  if $month eq "May";
    $mon = "06"  if $month eq "Jun";
    $mon = "07"  if $month eq "Jul";
    $mon = "08"  if $month eq "Aug";
    $mon = "09"  if $month eq "Sep";
    $mon = "10"  if $month eq "Oct";
    $mon = "11"  if $month eq "Nov";
    $mon = "12"  if $month eq "Dec";

    # Convert the time to the form: ##:##:##  (Notice two digits per!)
    #
    $time = sprintf ("%2.2d:%2.2d:%2.2d", "$hour", "$min", "$sec");

    # Convert the date to the form: ##:##:##
    #
    $date = sprintf ("%2.2d/%2.2d/%2.2d", "$mon", "$day", "$year");

#   print "Date = $date, Time = $time\n";

    return($date, $time);

} # getPinTime


################################################################################
#
# Subroutine    : getDateTime
#
# Description   : Gets System's date and time
#
################################################################################
sub getDateTime {

    my ($tt) = @_;

    ($sec, $min, $hr, $dom, $mon, $yr, $wday, $yday, $isdt) = localtime ($tt);
    $mon=$mon+1;
    $yr=$yr+1900;

    # Convert the date to the form: ##:##:##
    #
    $date = sprintf ("%2.2d/%2.2d/%2.2d", "$mon", "$dom", "$yr");

    # Convert the time to the form: ##:##:##  (Notice two digits!)
    #
    $time = sprintf ("%2.2d:%2.2d:%2.2d", "$hr", "$min", "$sec");

    return ($date, $time);
} # getDateTime

1;
