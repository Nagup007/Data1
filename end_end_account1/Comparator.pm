#!/home/pin/portal/ThirdParty/perl/5.8.0/bin/perl

#######################################################################
# This module makes a tree structure from the flist stream. Flists
# are already hierarchical but the same hierarchy is represented as
# a tree of hashes so that they can mirror the object hierarchy of
# the Flists.
#
# Each Node in the tree is just a hash. Which stores the follwing info.
# 1. level
# 2. Field Name
# 3. Data Type
# 4. Value
# Root node will be at level -1. So all flist 0 level elements
# will be hanging from this.
#
# Each node will be defined as given below.
# my $node = {
#                ############################
#                # The following data is
#                # associated with each node. 
#                ###########################
#   
#                NESTING_LEVEL => <NESTING LEVEL>,
#                DATA_TYPE     => <DATA TYPE>,
#                FIELD_NAME    => <FIELD_NAME>,
#                VALUE         => <VALUE>,
#                VALID_FLAG    => <TRUE or FALSE>, #  for expected flist only.
#                HASH_FLAG     => <TRUE or FALSE>  #  for expected flist only.
#                HASH_LINE     => <.hash..> #  Only if HASH_FLAG is TRUE.
#                STATUS        => <MATCH STATUS>,
#                LINE_NUM      => <FLIST LINE NUMBER>,
#                MARK          => <LABEL ON A LINE>,
#
#                ###############################
#                # The following refrences are
#                # the refrences to other nodes.
#                ###############################
#   
#                NEXT          => <REFRENCE TO THE NEXT IN THE SAME LEVEL>,
#                PREV          => <REFRENCE TO THE FATHER>,
#                SON           => <REFRENCE TO THE FIRST SON>,
#                ACTUAL        => <REFRENCE TO THE ACTUAL NODE>, # Applicable
#                                              for expected flist tree only.
#                EXPECTED      => <REFRENCE TO THE EXPECTED NODE>, # Applicable
#                                              for actual flist tree only.
#                PASS_COUNTS   => <COUNT OF PASSED VALIDATIONS>, # Applicable
#                                          for the root node of expected flist.
#           };
#######################################################################

#######################################################################
# Revision History
#
# $revision = '7.2-01';       # atul: initial creation
# $revision = '7.2-02';       # atul: Added pre match condition for
#                             # resource id in PIN_FLD_BALANCES arrays.
#######################################################################

package Comparator;

use strict;
use hashfile;

use vars qw($level @list @groupedlist %variables $MAX_LEVEL
            @ungroupedlist @explist %public_hash @child_exp @child_act
            @actlist @grexplist @gractlist); # To keep 'use strict' happy.

my $debug = 0;

my $showlinenum = 0;

my $large_opc_file = "FALSE";

############################################
# Class specific data will go in this block.
############################################

{   # <==== This brace is the start for class specific data.

my $opcode     = ();

my @rules      = ();

my $rulesFile  = "$ENV{'PIN_HOME'}/bin/opcoder.rules";

my $normactref = ();

my $match_type = "TOP_TO_BOTTOM";

my $extra_validation = "Pass";

if($debug)
{
    open(DEBUG, ">./debug.out");
}

################################################################################
# Subroutine    : setNormHashRef
# Description   : Sets the refrence to the normalization hash.
################################################################################
sub setNormHashRef
{
    $normactref = shift;
    return;
}

################################################################################
# Subroutine    : getNormHashRef
# Description   : Returns the refrence to the normalization hash.
################################################################################
sub getNormHashRef 
{
    return $normactref;
}

################################################################################
# Subroutine    : setMatchType
# Description   : Sets the match type.
################################################################################
sub setMatchType
{
    $match_type = shift;
    return;
}

################################################################################
# Subroutine    : getMatchType
# Description   : Returns the match type.
################################################################################
sub getMatchType 
{
    return $match_type;
}

################################################################################
# Subroutine    : setExtraValidation
# Description   : Sets the match type.
################################################################################
sub setExtraValidation
{
    $extra_validation = shift;
    return;
}

################################################################################
# Subroutine    : getExtraValidation
# Description   : Returns the match type.
################################################################################
sub getExtraValidation 
{
    return $extra_validation;
}

################################################################################
# Subroutine    : setOpcode
# Description   : Sets the opcode string for this testing.
################################################################################
sub setOpcode
{
    $opcode = shift;
    return;
}

################################################################################
# Subroutine    : getOpcode
# Description   : Returns the opcode string for this testing.
################################################################################
sub getOpcode 
{
    return $opcode;
}

################################################################################
# Subroutine    : getDebugFileHandle
# Description   : returns the debug file handle if the debug flag is enabled.
################################################################################
sub getDebugFileHandle
{
    if($debug)
    {
        return *DEBUG;
    }
    return;
}

################################################################################
# Subroutine    : getRules
# Description   : Gets all the values from the rules file
################################################################################
sub getRules
{
    my($line);       # contains each line read
    my($field);      # the actual field name of the line read.
    my($rule);       # the rule belonging to that field.
    my($opcode);     # the opcode from the rule line (first field).
    my($level);      # the level from the rule line (2nd field).
    my($lineNum);    # line counter.
    my($status);     # status flag.
    my($type);     # status flag.

    local *DEBUG = getDebugFileHandle() if($debug);

    if($debug)
    {
        print DEBUG "\nINFO: The opcoder rules file is : $rulesFile \n\n";
    }

    if ( $rulesFile )
    { 
        #############################################################################
        # A rules file location was passed as command line argument so try to open it
        #############################################################################
        open(RULES, "$rulesFile") || die "Unable to open rules file $rulesFile: $!\n";
    }
#    elsif ( -e "$defRulesFile" )
#    {
#        #####################################################
#        # Try to open the default rules file if there is one.
#        #####################################################
#        open(RULES, "$defRulesFile") ||
#            die "Unable to open default rules file $defRulesFile: $!\n";
#        $RULESFILE = "$defRulesFile";
#    } 

    ########################################
    # Now we have succesfully opened the rules file
    ########################################
    while( defined($line = <RULES>) ) 
    {
        $lineNum++;
        chop($line);
        next if $line =~ /^\s*(#|$)/;    # Skip empty lines and lines with comments

        ############################################################
        # Enforce this pattern to each rule, if not a match then raise the $status
        # flag to fail and print a syntax error.
        #
        # The following is an example of a rule syntax.
        # *: *:  PIN_FLD_LIMIT        : $status="Pass";
        # *: *: *:  is also legal
        # alternatively, we include the "type" field as follows ....
        # <opcode>: <level>: <field>: <type>: rule
        #############################################################

        if ( $line !~ /\s*(\w+|\*)\s*:\s*(\d+|\*)\s*:\s*(\w|\*)+\s*:.*/ )
        {
            print "Invalid Rule Syntax (line $lineNum)\n\"$line\"\n";
            $status = "Fail";
        }
        
        ##################################################
        # Extract opcode, level, field name and its rule (in that order)
        ##################################################
        ($opcode, $level, $field, $type, $rule) = split(/\s*:\s*/, $line);
        if (! $rule) 
        { 
            $rule = $type ; $type = ""; 
        }

        if ($type) 
        {
            push(@rules, "$opcode $level $field $type:$rule");
        }
        else
        {
             push(@rules, "$opcode $level $field:$rule");
        }
    }

    close(RULES);

    if($debug)
    {
        print DEBUG "\n", "\nINFO:", join "\n", @rules, "\n";
    }

    # If the $status flag was raised to Fail then exit the opcoder.
    #
    exit(1) if ((defined $status) and ($status eq "Fail"));
}

################################################################################
#
# Subroutine    : applyRules
#
# Description   : It applies rule(s) to corresponding field if any was loaded.
################################################################################

sub applyRules 
{
    my ($actual, $expected, $ActField, $ActOpcode, $ActLevel, $ActType) = @_;
    my  ($rule_select);
    my  ($entry);
    my  ($therule);
    my  ($ExpLevel, $ExpType);
    my  ($RulField, $RulOpcode, $RulLevel, $RulType);
    my ($LongActField, $status);
 
    local *DEBUG = getDebugFileHandle() if($debug);

    foreach my $entry (@rules) 
    {
       ($rule_select, $therule) = split(/:/, $entry);
       ($RulOpcode, $RulLevel, $RulField, $RulType) = split(/\s+/, $rule_select);

       ###################################
       # Set the wild card matches if appropriate
       ###################################
       $RulOpcode = $ActOpcode if $RulOpcode eq "*";
       $RulLevel = $ActLevel if $RulLevel eq "*";
       $RulField = $ActField if $RulField eq "*";
       $RulType = $ActType if (! $RulType) || ($RulType eq "*");

      if ($RulField eq $ActField) 
      {
          ###########################################
          # Get opcode name from defines array if necessary
          # CHECK: Need to use PCM defines.
          ###########################################
 
          #$RulOpcode = getPcmDefines($RulOpcode);

          ############################################
          # Construct Comparison lines
          ###########################################
          $RulField = "$RulOpcode $RulLevel $RulField $RulType";
          $LongActField = "$ActOpcode $ActLevel $ActField $ActType";

          if ( $RulField eq $LongActField ) 
          {
              # An exact match was found so apply rule
              no strict;
              eval $therule;    # evaluate the rule--Perl takes over
              return $status;
          }
       }
   }
}


}  #end of class specific data.

#######################################################################
# Subroutine Name: treeNode
# Description    : Creates a tree node. The refrence to this can be
#                  assigned to the already existing nodes.
#######################################################################
 
sub treeNode ()
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $node = {};
    if(@_)
    {
         $node = shift; 
    }
    else    # This is root node.
    {
        $node->{FIELD_NAME} = "PIN_FLD_ROOT_NODE";
        $node->{NESTING_LEVEL} = -1;
        $node->{DATA_TYPE} = "ARRAY";
        $node->{VALUE} = "root";
        $node->{STATUS} = ();
    }

    bless $node, $class;
    return $node;
}

##########################################################################
# Subroutine Name: buildFlistTreeFromFlistString
# Description: This function cretaes an flist tree from flist stream.
# Usage: $comprator->flistFromString($flist_string);
#                     PREV
#                      -->  ROOT<- PREV        Level : -1 
#                     /           \
#                    /     /|\     \
#                   /     / | \     \
#                  /     /  |  \     \
#                 |     /   |   \     \
#                 |    /    |    \     \
#                 |   /     |     \     \
#                 |  /      |      \    |
#                 | /       |       \   |
#                 |/        |        \  |
#                 SON----->NEXT------>NEXT     Level : 0 
#                / | \
#               /  |  \
#              /   |   \
#             /    |    \
#            /     |     \
#           /      |      \
#          /       |       \
#         /        |        \
#        SON----->NEXT------>NEXT              Level : 1
# Notes:
# 1. A Son or next node will be a leaf if it has no sons
##########################################################################

sub buildFlistTreeFromFlistString( )
{
    my ($self) = shift;
    my ($string) = shift;

    my ($prev)  = $self;
    my ($prev_level) =  -1;
    my ($line_num) = 0;

    my ($VALIDATE_FLAG) = ();
    my ($HASH_FLAG) = "FALSE";
    my (@HASH_LINE) = ();
    my ($MARK) = ();

    my @flist = split("\n", $string);
    foreach my $line (@flist)
    {
        $line_num ++;
        chomp ( $line );
        if($line eq "")
        {
            next;
        }
        if($line =~ /^\s*#/)
        {
            next;
        }
        if($line =~ /\.validate/)
        {
            if($line =~ /fail/i)
            {
                $VALIDATE_FLAG = "FALSE";
            }
            elsif($line =~ /absent/i)
            {
                $VALIDATE_FLAG = "ABSENT";
            }
            elsif($line =~ /fieldname/i)
            {
                $VALIDATE_FLAG = "FIELDNAME";
            }
            elsif($line =~ /off/i)
            {
                $VALIDATE_FLAG = "OFF";
            }
            elsif($line =~ /errcode/i)
            {
                $VALIDATE_FLAG = "ERRCODE";
            }
            else
            {
                $VALIDATE_FLAG = "TRUE";
            }
            next;
        }
        if($line =~ /\.mark *$/i)
        {
            $MARK = " NEW";
            next
        }
        if($line =~ /\.mark +(\S+)/i)
        {
            $MARK = " $1";
            next;
        }
        if($line =~ /\.hash/)
        {
            $HASH_FLAG = "TRUE";
            push(@HASH_LINE,$line);
            next;
        }
        $line =~ s/^\s*(.*)/$1/;
        my($level, $field_name, $data_type, $value) =
                                     split(/\s+/, $line, 4);
        ##################################
        # Remove extra hexadecimal numbers
        # in the begining of value field.
        # e.g: STR 0x656c [0] "invcsr1a"
        ##################################
        $value =~ s/^0x[0-9A-Fa-f]+\s+(\[\d\]\s+)/$1/;

        ##################################
        # If level is not numeric. Go next
        ##################################
        if($level =~ /[^0-9]/)
        {
            $prev->{VALUE} = $prev->{VALUE}."  ".$line
                     if(($prev->{DATA_TYPE} eq "ERR") or
                       ($prev->{DATA_TYPE} eq "BUF"));
            next;
        }
        if(!((defined $level) and (defined $field_name)
             and (defined $data_type)))
        {
            $line = ();
            next;
        }

        ##################################
        # Enforce Validation for ERR_BUF
        # and disable it for certain fields.
        ##################################
        $VALIDATE_FLAG = "TRUE"
                 if(($field_name =~ /PIN_FLD_ERR_BUF/) and
                    (!defined $VALIDATE_FLAG));

        $VALIDATE_FLAG = () if ($line =~ /ITEM_POID_LIST\s/) or
                               ($line =~ /INVOICE_DATA\s/) or
                               ($line =~ /\sARRAY\s/);

        my($node) = {};
        $node->{NESTING_LEVEL} = $level;
        $node->{DATA_TYPE} = $data_type;
        $node->{FIELD_NAME} = $field_name;
        $node->{VALUE} = $value;
        if(defined $VALIDATE_FLAG)
        {
            $node->{VALID_FLAG}=$VALIDATE_FLAG;
            $VALIDATE_FLAG = ();
        }
        if($HASH_FLAG eq "TRUE" )
        {
            $node->{HASH_FLAG}="TRUE";
            my @hasharray = @HASH_LINE;
            $node->{HASH_LINE}=\@hasharray;
            @HASH_LINE = ();
            $HASH_FLAG = "FALSE";
        }
        if(defined $MARK)
        {
            $node->{MARK}=$MARK;
            $MARK = ();
        }

        ####################################
        # Add line num in node for debugging.
        ####################################
        $node->{LINE_NUM} = $line_num;

        #####################################
        # Mark the file as large opc file. If
        # number of lines in flist are > 5000.
        #####################################
        $large_opc_file = "TRUE" if($line_num > 5000);

        ######################
        # For extra validation.
        ######################
        if($field_name eq "PIN_FLD_STATUS")
        {
            $node->{EXTRA_VALIDATION}="TRUE";
        }

        ######################
        # Bless this refrence.
        ######################
        $node = Comparator->treeNode($node);

        if($level == $prev_level+1)
        {
            $prev->{SON}=$node;
            $node->{PREV}=$prev;
        }
        if($level == $prev_level)
        {
            $prev->{NEXT}=$node;
            $node->{PREV}=$prev->{PREV};
       }
       if($level < $prev_level)
       {
           while($prev_level > $level)
           {
              $prev=$prev->{PREV};
               $prev_level--;
          }
          $prev->{NEXT}=$node;
          $node->{PREV}= $prev->{PREV};
       }
       $prev=$node;
       $prev_level = $level;
   }
}

##########################################################################
# Subroutne   : dumpFlistStringFromFlistTree
# Description : This routine dumps the flist from the flist tree.
#               This is a sort of accessor method  class which can
#               be used for debugging purpose.
##########################################################################

sub dumpFlistStringFromFlistTree()
{
    my ($self) = shift;
    local (*LOGFILE) = shift;

    print LOGFILE "$self->{NESTING_LEVEL}",
                  "  " x $self->{NESTING_LEVEL},
                  " $self->{FIELD_NAME}", "\t\t",
                  "$self->{DATA_TYPE}",
                  " $self->{VALUE}",;
    if(defined $self->{EXTRA_VALIDATION})
    {
        print LOGFILE "   EXTRA VALIDATION ENABLED   ";
    }
    if(defined $self->{STATUS})
    {
        print LOGFILE "   =====>   $self->{STATUS}\n";
    }
    else
    {
        print LOGFILE "\n";
    }
    if(defined $self->{SON}) { $self->{SON}->dumpFlistStringFromFlistTree(*LOGFILE); }

    if(defined $self->{NEXT}) { $self->{NEXT}->dumpFlistStringFromFlistTree(*LOGFILE); }

}

##########################################################################
# Subroutne   : matchAllArraysInFlist ()
# Description : This subroutine matches all the array elements in the
#               expected and actual flists.
##########################################################################

sub matchAllArraysInFlist ()
{
    my $self      = shift;
    my $exp_flist = shift; 
    my $act_flist = shift;
    my $opcode    = shift;
    local (*public_hash) = shift;
    local (*variables) = shift;
    my ($normref) = shift;
    local (*LOGFILE) = shift; 
    $showlinenum  = shift;
    my $max_level = ();
    my $status  = "Pass";

    ##############################
    # Reset large_opc_file flag on
    # each call to match routine.
    ##############################
    $large_opc_file = "FALSE";

    local *DEBUG = getDebugFileHandle() if($debug);

    $opcode = "UNKNOWN_OPCODE" if(! defined $opcode);

    ##############################
    # Set the opcode string value.
    ##############################
    setOpcode($opcode);

    #############################
    # Initialize rules.
    #############################
    &getRules;

    #############################
    # Set normalization hash. 
    #############################
    setNormHashRef($normref);

    #############################
    # Build Expected flist tree.
    #############################
    
    my $expref=Comparator->treeNode();
    $expref->buildFlistTreeFromFlistString($exp_flist);

    #############################
    # Build Actual flist tree.
    #############################

    my $actref=Comparator->treeNode();
    $actref->buildFlistTreeFromFlistString($act_flist);

    if($debug)
    {
        print DEBUG "\n###############################\n";
        print DEBUG "# Expected Flist before matching:";
        print DEBUG "\n###############################\n\n";
       $expref->{SON}->dumpFlistStringFromFlistTree(*DEBUG)
                                    if(defined $expref->{SON});
        print DEBUG "\n###############################\n";
        print DEBUG "# Actual Flist dump before matching:";
        print DEBUG "\n###############################\n\n";
        $actref->{SON}->dumpFlistStringFromFlistTree(*DEBUG)
                                    if(defined $actref->{SON});
    }
    ####################################
    # Replace the valid %varN values.
    ####################################

    $expref->replaceValidVariables(*variables);

    my $exparray = [ $expref ];
    my $actarray = [ $actref ];

    #####################################################
    # This is the main match routine of this module. This
    # routine will call itself recursively till all the
    # elements in expected and actual tree are matched.
    #####################################################

    setMatchType("TOP_TO_BOTTOM");
    setExtraValidation("Pass");
    matchTwoGroupedArrays($exparray, $actarray);

    if($debug)
    {
        print DEBUG "\n##########################################\n";
        print DEBUG "# Expected Flist dump after matching is over:";
        print DEBUG "\n##########################################\n\n";
        $expref->{SON}->dumpFlistStringFromFlistTree(*DEBUG)
                                    if(defined $expref->{SON});
        print DEBUG "\n##########################################\n";
        print DEBUG "# Actual Flist dump after matching is over:";
        print DEBUG "\n##########################################\n\n";
        $actref->{SON}->dumpFlistStringFromFlistTree(*DEBUG)
                                    if(defined $actref->{SON});
    }

    ###############################
    # Mark root for Pass or Fail.
    ###############################

    if(defined $expref->{SON})
    {
        $expref->{STATUS} = ();
        $expref->{PASS_COUNTS} = 0;
        $expref->{SON}->markRootForPassOrFail($expref);
        $status = $expref->{STATUS}
               if(defined $expref->{STATUS});
    }

    my $extra_validation = getExtraValidation();

    #########################################
    # If opc file is too large. There is no
    # need to do BOTTOM_TO_TOP match. It will
    # cause unnecessary delay. 
    #########################################

    if(($large_opc_file eq "FALSE") and
       (($status eq "Fail") or
       ($extra_validation eq "Fail")))
    {
        #############################
        # Build the trees.
        #############################

        my $expref1=Comparator->treeNode();
        $expref1->buildFlistTreeFromFlistString($exp_flist);

        my $actref1=Comparator->treeNode();
        $actref1->buildFlistTreeFromFlistString($act_flist);

        ####################################
        # Replace the valid %varN values.
        ####################################
        $expref1->replaceValidVariables(*variables);

        ######################################
        # Set Match Type and extra validation.
        ######################################

        setMatchType("BOTTOM_TO_TOP");
        setExtraValidation("Pass");
        my $status1 = "Pass";

        ####################################
        # match the trees from bottom to top
        ####################################

        matchFromBottomToTop($expref1, $actref1, $exp_flist);


        if(defined $expref1->{SON})
        {
            $expref1->{STATUS} = ();
            $expref1->{PASS_COUNTS} = 0;
            $expref1->{SON}->markRootForPassOrFail($expref1);
            $status1 = $expref1->{STATUS}
                   if(defined $expref1->{STATUS});
        }

        my $extra_validation1 = getExtraValidation();

        if($status eq "Fail")
        {
            if(($status1 ne "Fail") or
               ($expref1->{PASS_COUNTS} > $expref->{PASS_COUNTS}))
            {
                $expref=$expref1;
                $actref=$actref1;
                $status = $status1;
            }
            else
            {
                setMatchType("TOP_TO_BOTTOM");
            }
        }
        if(($status ne "Fail") and ($extra_validation eq "Fail"))
        {
            if(($status1 ne "Fail") and ($extra_validation1 ne "Fail"))
            {
                $expref=$expref1;
                $actref=$actref1;
                $status = $status1;
            }
            else
            {
                setMatchType("TOP_TO_BOTTOM");
            }

        }
    }

    ###############################
    # update %public_hash values.
    ###############################

    $expref->getHashFromFlist(*public_hash);

    ##################################
    # Set the %varN values.
    ##################################
    $expref->getVarsFromFlist(*variables);

    if($debug)
    {
        print DEBUG "\n##############\n";
        print DEBUG " %varN values : ";
        print DEBUG "\n##############\n";

        foreach my $key (keys %variables)
        {
            print DEBUG "$key => $variables{$key}\n";
        }
    }

    ##################################
    # replace the variable in expected
    # with the actual values.POID etc...
    ##################################

    $expref->replaceVariableValues();

    ###############################
    # Add all missing fields in
    # expected tree.
    ###############################

    $actref->addMissingFieldsInTree();

    if($debug)
    {
        print DEBUG "\nThe value of status = $status\n\n";
    }

    ###############################
    # Print results.
    ###############################

    printResults ($opcode, $status, *LOGFILE, $expref );

    ###############################
    # Close debug file handle.
    ###############################

    close(DEBUG);

    return $status;
}

##########################################################################
# Subroutne   : matchTwoGroupedArrays
# Description : This matches two grouped arrays and sets refrences of actual
#             : in expected for a best match condition.
##########################################################################

sub matchTwoGroupedArrays ()
{
    my ($expgroup, $actgroup) = @_;

    my ($prevarray) = ();
    my ($prev_score) = ();
    my ($prev_valid_passes) = ();
    my ($defaultMatch) = "Fail";

    foreach my $exparray (@$expgroup)
    {
        my $MAX_SCORE = getScore($exparray, 1);
        resetExpectArrayOrSubstruct($exparray);

        foreach my $actarray (@$actgroup)
        {
            #####################################
            # If array node has diffrent field
            # names or data type, take next.
            #####################################

            if(($exparray->{FIELD_NAME} ne $actarray->{FIELD_NAME}) or
               ($exparray->{DATA_TYPE} ne $actarray->{DATA_TYPE}))
            {
                next; 
            }
            ######################################
            # If actual array has aleady matched
            # someone in expected group. take next.
            #######################################

            if((defined $actarray->{STATUS}) and
               ($actarray->{STATUS} eq "MATCH_DONE"))
            {
                next;
            }
            ##########################################
            # If only one array is remaining in both
            # actual and expected group. Then that is
            # the condition of default match.
            ##########################################

            if((getRemainingCount($expgroup, $exparray->{FIELD_NAME}) == 1) and
               (getRemainingCount($actgroup, $actarray->{FIELD_NAME}) == 1))
            {
                $defaultMatch = "True";
            }

            #########################################
            # If default match fails. check the field
            # name and poid object if they exist and
            # check resource id for PIN_FLD_BALANCES. 
            #########################################

            if($defaultMatch eq "Fail")
            {
               if((IsCorrectPoidMatch($exparray, $actarray) eq "Fail") or
                  (IsCorrectFieldNameInArray($exparray, $actarray) eq "Fail"))
               {
                   next;
               }
               if(($exparray->{FIELD_NAME} eq "PIN_FLD_BALANCES") and
                  ($exparray->{DATA_TYPE} eq "ARRAY") and
                  (IsCorrectResourceIdMatch($exparray, $actarray) eq "Fail"))
               {
                   next;
               }
            }

        
            #####################################
            # Perform an array match. Before that
            # do clean up.
            #####################################

            resetArrayStatus($prevarray);
            resetArrayStatus($actarray);
            resetArrayStatus($exparray);
            resetExpectArrayOrSubstruct($exparray);

            $exparray->matchArrayOrSubstructElements($actarray);
            my $score = getScore($exparray, 0);
            my $valid_passes = $exparray->validPassCount();

            if( $score >= $MAX_SCORE)
            {
                $prevarray=$actarray;
                last;
            }
            elsif (((defined $prev_score) and ($prev_score > $score))  or
                   ((defined $prev_score) and ($prev_score == $score) and 
                    ($prev_valid_passes >= $valid_passes)))
            {
                #######################################
                # Set all the previous refrences again.
                # Before that clean up everything.
                #######################################

                resetArrayStatus($prevarray);
                resetArrayStatus($exparray);
                resetArrayStatus($actarray);
                resetExpectArrayOrSubstruct($exparray);

                $exparray->matchArrayOrSubstructElements($prevarray);
            }
            else
            {
                $prev_score = $score;
                $prevarray = $actarray;
                $prev_valid_passes = $exparray->validPassCount();
            }
        }
        if(defined $prevarray)
        {
            matchValues($exparray, $prevarray);
            $prevarray->{STATUS} = "MATCH_DONE";
        }
        else
        {
            $exparray->createMissingActualNode();
            $exparray->{STATUS} = "NOT_FOUND";
        }

        if( getMatchType() eq "TOP_TO_BOTTOM" )
        {
            my @expgr = ();
            my @actgr = ();
            my $exp = $exparray->{SON};
            while(defined $exp)
            {
                if(($exp->{DATA_TYPE} eq "ARRAY") or
                  ($exp->{DATA_TYPE} eq "SUBSTRUCT"))
                {
                    push(@expgr, $exp);
                }
                $exp = $exp->{NEXT};
            }
            my $act = $prevarray->{SON};
            while(defined $act)
            {
                if(($act->{DATA_TYPE} eq "ARRAY") or
                   ($act->{DATA_TYPE} eq "SUBSTRUCT"))
                {
                    push(@actgr, $act);
                }
                $act = $act->{NEXT};
            }
            ################################################
            # Recursive call to the matchTwoGroupedArrays ()
            # This is called only if we have a group of
            # child expected arrays.
            ################################################
            &matchTwoGroupedArrays(\@expgr, \@actgr)
                                        if(@expgr);
        }
        $prevarray = ();
        $prev_score = ();
    }
    return;
}

##########################################################################
# Subroutne : matchArrayOrSubstructElements
# Description : This subroutine matches two arrays and sets the status.
##########################################################################

sub matchArrayOrSubstructElements()
{
    my ($self) = shift;
    my($actarray) = shift;

    ###Sanity Check
    ###Add here. FIELD_NAME, LEVEL AND DATA_TYPE check. 

    my ($expref) = $self->{SON};
    while($expref)
    {
        if(($expref->{DATA_TYPE} eq "ARRAY") or
           ($expref->{DATA_TYPE} eq "SUBSTRUCT"))
        {
            $expref=$expref->{NEXT};
            next;
        }
        my $actref=$actarray->{SON};
        while($actref)
        {
             if(($expref->{NESTING_LEVEL} == $actref->{NESTING_LEVEL}) and
                ($expref->{DATA_TYPE} eq $actref->{DATA_TYPE}) and
                ($expref->{FIELD_NAME} eq $actref->{FIELD_NAME}))
             {
                 matchValues($expref, $actref);
                 last;
             }
             $actref=$actref->{NEXT};
         } 
         $expref=$expref->{NEXT};
    }
    return;
}

##########################################################################
# Subroutne : matchValues
# Description : This subroutine matches the values in two nodes. 
##########################################################################
sub matchValues
{
    my($expref, $actref) = @_;
    my $numeric = "INT|ENUM|DECIMAL";

    my $expval = $expref->{VALUE};
    $expval =~ s/^\[\d+\]\s*(.*)\s*$/$1/;
    ## To remove quotes (") on the borders. 
    $expval =~ s/^\s*"\s*//g;
    $expval =~ s/\s*"\s*$//g;

    my $actval = $actref->{VALUE};
    $actval =~ s/^\[\d+\]\s*(.*)\s*$/$1/;
    ## To remove quotes (") on the borders. 
    $actval =~ s/^\s*"\s*//g;
    $actval =~ s/\s*"\s*$//g;

    ########################
    # Do normalization here.
    ########################
    ($expval, $actval) =
          doNormAct($expval, $actval,
                    $expref->{FIELD_NAME}, $expref->{DATA_TYPE});

    ######################
    # Set wild card match.
    ######################
    if ($expval =~ /^%$/)
    {
        my $vtmp = ();
        ($vtmp = $expval) =~ s/%/.*/;
        if ($actval =~ /$vtmp/)
        {
            $expval = $actval;      # for the compare, they MUST match
        }
    }
        
    ################
    # Apply Rules.
    ################

    my $OPCODE = getOpcode();

    my $status = applyRules($actval, 
               $expval,
               $expref->{FIELD_NAME},
               $OPCODE,
               $expref->{NESTING_LEVEL},
               $expref->{DATA_TYPE});

    if((defined $status) and ($status eq "Pass"))
    {
        $expref->{STATUS} = "MATCH_PASSED";

        if(defined $expref->{VALID_FLAG})
        {
            ###################################################
            # If this is a -ve case then. check that if nothing
            # is expected and there is something in actual. I am
            # putting the status as NOT_FOUND, so that final status
            # will be shown as SFail for backward compatibility.
            ####################################################
            if(($expref->{VALID_FLAG} eq "FALSE") and ($expval eq "") and ($actval ne ""))
            {
                $expref->{STATUS} = "NOT_FOUND";
            }
            elsif($expref->{DATA_TYPE} eq "TSTAMP")
            {
                $expval = $1 if($expval =~ m/^\((.*)\).*/);
                $actval = $1 if($actval =~ m/^\((.*)\).*/);
                $expref->{STATUS} = "MATCH_FAILED" if($expval ne $actval);
            }
        }
    }
    elsif($expref->{FIELD_NAME} eq "PIN_FLD_ERR_BUF")
    {
        #############################
        # PIN_FLD_ERR_BUF validation.
        #############################
        $expval =~ s/^.*errno=(PIN_ERR_.*):\d*>.*field num.*$/$1/;
        $actval =~ s/^.*errno=(PIN_ERR_.*):\d*>.*field num.*$/$1/;

        if((defined $expref->{VALID_FLAG}) and
              ($expref->{VALID_FLAG} eq "ERRCODE"))
        {
            if($expval eq $actval)
            {
                $expref->{STATUS} = "MATCH_PASSED";
            }
            else
            {
                $expref->{STATUS} = "MATCH_FAILED";
            }
            $expref->{VALID_FLAG} = "TRUE";
        }
        else
        {
            $expref->{STATUS} = "MATCH_PASSED";
        }
    }
    elsif(($expref->{DATA_TYPE} eq "BUF") or
          ($expref->{DATA_TYPE} eq "ERR"))
    {
        $expval=~ s/\s+/ /g;
        $actval=~ s/\s+/ /g;

        if($expval eq $actval)
        {
            $expref->{STATUS} = "MATCH_PASSED";
        }
        else
        {
            $expref->{STATUS} = "MATCH_FAILED";
        }
    }
    elsif($expref->{DATA_TYPE} eq "POID")
    {
        ##################################
        #If the POID has come. check the
        # storable class name and leave it.
        ##################################
        my @expval = split(/\s+/, $expval);
        my $exp_db_no = $expval[0];
        my $exp_storable = $expval[1];
        my $exp_poid_val = $expval[2];

        my @actval = split(/\s+/, $actval);
        my $act_db_no = $actval[0];
        my $act_storable = $actval[1];
        my $act_poid_val = $actval[2];

        if(($exp_storable eq $act_storable) and
          ($exp_db_no eq $act_db_no))
        {
            if(($exp_poid_val =~ /%var/) or
               ($exp_poid_val == $act_poid_val))
            {
                $expref->{STATUS} = "MATCH_PASSED";
            }
            else
            {
                $expref->{STATUS} = "MATCH_FAILED";
            }
        }
        else
        {
            $expref->{STATUS} = "MATCH_FAILED";
        }
    }
    elsif($expref->{DATA_TYPE} =~ /($numeric)/)
    {
        $expval = 0 if($expval =~ /NULL/i);
        $actval = 0 if($actval =~ /NULL/i);

        if(($expval =~ /%var/) or ($expval == $actval))
        {
            $expref->{STATUS} = "MATCH_PASSED";
        }
        else
        {
            $expref->{STATUS} = "MATCH_FAILED";
        }
    }
    else
    {
        $expval = "NULL" if($expval =~ /NULL/i);
        $actval = "NULL" if($actval =~ /NULL/i);
        if($expref->{DATA_TYPE} eq "TSTAMP")
        {
            if(defined $expref->{VALID_FLAG})
            {
                $expval = $1 if($expval =~ m/^\((.*)\).*/);
                $actval = $1 if($actval =~ m/^\((.*)\).*/);
            }
            else
            {
                $expval = $actval;
            }
        }

        if(($expval =~ /%var/) or ($expval eq $actval))
        {
            $expref->{STATUS} = "MATCH_PASSED";
        }
        else
        {
            $expref->{STATUS} = "MATCH_FAILED";
        }
    }

    ##################################
    # refrence of actual node in the
    # expected node.
    ##################################

    $expref->{ACTUAL} = $actref;
    $actref->{STATUS} = "MATCH_DONE";
    $actref->{EXPECTED} = $expref;

    return;
}

##########################################################################
# Subroutne   : resetArrayStatus
# Description : This function clears the status info from a subroutine.
##########################################################################

sub resetArrayStatus()
{
    my ($array) = shift;

    my $temp = $array->{SON};
    while($temp)
    {
        if(!(($temp->{DATA_TYPE} eq "ARRAY") or
            ($temp->{DATA_TYPE} eq "SUBSTRUCT")))
        {
            $temp->{STATUS} = ()
                 if(defined $temp->{STATUS});
            $temp->{ACTUAL} = ()
                 if(defined $temp->{ACTUAL});
            $temp->{EXPECTED} = ()
                 if(defined $array->{EXPECTED});
        }
        $temp = $temp->{NEXT};
    }
    return;
}

##########################################################################
# Subroutne   : markRootForPassOrFail
# Description : This subroutine matches the expected and actual
#               remaining elements.
##########################################################################

sub markRootForPassOrFail ()
{
    my $self = shift;
    my $rootref = shift;

    ###################
    # Extra Validation.
    ###################

    if(defined $self->{EXTRA_VALIDATION})
    {
        setExtraValidation("Fail")
                if($self->{STATUS} ne "MATCH_PASSED");
    }

    ###########################################
    # Test for +ve validation. (.validate)
    ###########################################

    if((defined $self->{VALID_FLAG}) and
       ($self->{VALID_FLAG} eq "TRUE"))
    {
        if((defined $self->{STATUS}) and
           ($self->{STATUS} eq "MATCH_PASSED"))
        {
            $self->{STATUS}="Pass";
            $rootref->{PASS_COUNTS}++;
        }
        else
        {
            $self->{STATUS}="Fail";
            $rootref->{STATUS}="Fail";
        }
    }

    ###########################################
    # Test for -ve validation. (.validate fail)
    ###########################################

    elsif((defined $self->{VALID_FLAG}) and
       ($self->{VALID_FLAG} eq "FALSE"))
    {
        if((defined $self->{STATUS}) and
           ($self->{STATUS} eq "MATCH_FAILED"))
        {
            $self->{STATUS}="Pass";
            $rootref->{PASS_COUNTS}++;
        }
        elsif((defined $self->{STATUS}) and
           ($self->{STATUS} eq "NOT_FOUND"))
        {
            $self->{STATUS}="SFail";
            $rootref->{PASS_COUNTS}++;
        }
        else
        {
            $self->{STATUS}="Fail";
            $rootref->{STATUS}="Fail";
        }
    }

    ###########################################
    # Test for absent validation. (.validate absent)
    ###########################################

    elsif((defined $self->{VALID_FLAG}) and
       ($self->{VALID_FLAG} eq "ABSENT"))
    {
        if((defined $self->{STATUS}) and
           ($self->{STATUS} eq "NOT_FOUND"))
        {
            $self->{STATUS}="Pass";
            $rootref->{PASS_COUNTS}++;
        }
        else
        {
            $self->{STATUS}="Fail";
            $rootref->{STATUS}="Fail";
        }
    }

    ###########################################
    # Test for field name validation. (.validate fieldname)
    ###########################################

    elsif((defined $self->{VALID_FLAG}) and
       ($self->{VALID_FLAG} eq "FIELDNAME"))
    {
        if((defined $self->{STATUS}) and
           ($self->{STATUS} ne "NOT_FOUND"))
        {
            $self->{STATUS}="Pass";
            $rootref->{PASS_COUNTS}++;
        }
        else
        {
            $self->{STATUS}="Fail";
            $rootref->{STATUS}="Fail";
        }
    }

    ###########################################
    # Test for no validation.
    ###########################################

    else
    {
        if((defined $self->{STATUS}) and
           ($self->{STATUS} eq "MATCH_PASSED"))
        {
            $self->{STATUS}="Pass";
        }
        else
        {
            $self->{STATUS}="Warn";
            $rootref->{STATUS}="Warn" if(!defined $rootref->{STATUS});
        }
    }

    if(defined $self->{SON}) { $self->{SON}->markRootForPassOrFail($rootref); }

    if(defined $self->{NEXT}) { $self->{NEXT}->markRootForPassOrFail($rootref); }

    return;
}

##########################################################################
# Subroutne   : printResults
# Description : This subroutine prints the results in .out file.
##########################################################################

sub printResults ()
{
    my ($opcode)    = shift;
    my ($status)    = shift;
    local(*LOGFILE) = shift;
    my ($expref)    = shift;

    my ($date, $time) = hashfile::getDateTime(time());
    my ($pdate, $ptime) = hashfile::getPinTime();

    my ($match_type) = getMatchType();
    print LOGFILE "\nMATCH TYPE : $match_type  \n";
    print LOGFILE "\n\t\t\t OPCODER REPORT \n";
    print LOGFILE "\t\t\t ============== \n";
    printf(LOGFILE "Opcode Test Summary: %-35s Time: %s-%s  PIN Time: %s-%s  %s\n",
                    $opcode, $date, $time, $pdate, $ptime, $status);
    print LOGFILE "-" x120, "\n";

    printHeader(*LOGFILE);
    $expref->{SON}->newPrint(*LOGFILE)
                  if defined $expref->{SON};
    printFooter(*LOGFILE);

    return;    
}

##########################################################################
# Subroutne   : getHashFromFlist
# Description : This subroutine gets new hash values from the expected
#               flist tree.
##########################################################################

sub getHashFromFlist ()
{
    my ($self) = shift;
    local (*public_hash) = shift;

    local *DEBUG = getDebugFileHandle() if($debug);

    if ((defined $self->{HASH_FLAG}) and
        ($self->{HASH_FLAG} eq "TRUE"))
    {
        foreach my $HASH_LINE (@{$self->{HASH_LINE}})
        {
            $HASH_LINE =~ s/^\s*(.*)/$1/;
            my $subfield = "";
            my $junk = "";
            my $key = "";
            ($junk, $key, $subfield) = split(/\s+/, $HASH_LINE);
            if($self->{ACTUAL}->{VALUE} =~ /Missing field/)
            {
                $public_hash{$key} = ""; 
            }
            else
            {
                $public_hash{$key} = getValue ($self->{ACTUAL}->{VALUE},
                                               $subfield) ;
            }
            if($debug)
            {
                print DEBUG "\n The hash line is :\n", "$HASH_LINE", "\n";
                print DEBUG "\n The key line is :\n", "$key", "\n";
                print DEBUG "\n The subfield line is :\n", "$subfield", "\n" if($subfield);
                print DEBUG "\n The actual value is :\n", "$self->{ACTUAL}->{VALUE}", "\n";
                print DEBUG "\n The hash value is :\n", "$public_hash{$key}", "\n";
                print DEBUG "-" x30, "\n";
            }
        }
    }

    if(defined $self->{SON}) { $self->{SON}->getHashFromFlist(*public_hash); }

    if(defined $self->{NEXT}) { $self->{NEXT}->getHashFromFlist(*public_hash); }

    return;
}

##########################################################################
# Subroutne   : getVarsFromFlist
# Description : This subroutine extracts the %varN values from the
#               expected flist tree.
##########################################################################

sub getVarsFromFlist ()
{
    my ($self) = shift;
    local (*variables) = shift;

    local *DEBUG = getDebugFileHandle() if($debug);

    if ((defined $self->{VALUE}) and ($self->{VALUE} =~ /%var/))
    {
        if((defined $self->{ACTUAL}->{VALUE}) and 
           ($self->{ACTUAL}->{VALUE} !~ /Missing field/))
        {
            my @exp = split(/\s+/, $self->{VALUE});
            my @act = split(/\s+/, $self->{ACTUAL}->{VALUE});
            my $i=1;
            while($i <= $#exp)
            {
                if($exp[$i] =~ /%var/)
                {
                    $variables{$exp[$i]} = $act[$i];

                    ################################
                    # If POID is unintialized then
                    # set it to 999 again.
                    ################################
                    if(($self->{DATA_TYPE} eq "POID") and
                       ($act[$i] == 0))
                    {
                        $variables{$exp[$i]} = 999;
                    }
                    last;
                }
                $i++;
            }
        }
    }
    if(defined $self->{SON}) { $self->{SON}-> getVarsFromFlist(*variables); }

    if(defined $self->{NEXT}) { $self->{NEXT}-> getVarsFromFlist(*variables); }

    return;
}

##########################################################################
# Subroutne   : replaceValidVariables
# Description : This subroutine replaces the valid %varN values in the 
#               expected flist.
##########################################################################

sub replaceValidVariables ()
{
    my ( $self ) = shift;
    local ( *variables) = shift;

    if(! defined (keys %variables))
    {
        return;
    }

    if(( defined $self->{VALUE}) and
       ($self->{VALUE} =~ /^(.*)(%var\d+)(.*)$/))
    {
        if( -f "$ENV{PIN_HOME}/lib/5.8.0/warnings.pm")
        {
            eval "no warnings";
        }
        if((defined $variables{$2})    and
           ($variables{$2} != 999)     and
           ($variables{$2} !~ /"999"/))
        {
            $self->{VALUE} =  $1.$variables{$2}.$3
        }
             
    }

    if(defined $self->{SON}) { $self->{SON}->replaceValidVariables(*variables); }

    if(defined $self->{NEXT}) { $self->{NEXT}->replaceValidVariables(*variables); }

    return;
}

##########################################################################
# Subroutne   : getValue
# Description : This subroutine returns the value of hash variable.
##########################################################################

sub getValue 
{
    my ($line, $valfield) = @_;
    (my $val = $line) =~ s/.*\] +(.*)/$1/;

    if ($valfield)
    {
         my @vals = split / +/, $val;
         $val = $vals[$valfield - 1];
    }
    return ($val);

}

##########################################################################
# Subroutne   : getScore
# Description : This subroutine returns the maximum score.
##########################################################################

sub getScore ()
{
    my $array = shift;
    my $flag = shift;
    my $score = 0;

    my $temp = $array;
    $temp=$temp->{SON};
    while(defined $temp)
    {
        if(!(($temp->{DATA_TYPE} eq "ARRAY") or
            ($temp->{DATA_TYPE} eq "SUBSTRUCT")))
        {
            if($flag == 0)
            {
                if((defined $temp->{STATUS}) and
                   ($temp->{STATUS}  eq "MATCH_PASSED"))
                {
                    $score++;
                }
            }
            else
            {
                $score++;
            }
        }
        $temp=$temp->{NEXT};
    }
    return $score;
}

##########################################################################
# Subroutne   : getRemainingCount
# Description : This subroutine returns the Remaining array count.
##########################################################################

sub getRemainingCount()
{
    my $group = shift;
    my $field_name = shift;

    my $count = 0;

    foreach my $array (@$group)
    {
        $count++
            if((!defined $array->{STATUS}) and
               ($array->{FIELD_NAME} eq $field_name));
    }
    return $count;
}

##########################################################################
# Subroutne   : IsCorrectFieldNameInArray
# Description : This subroutine checks that if an array has PIN_FLD_NAME,
#               then it matches with the PIN_FLD_NAME field which has same
#               storable class and DB no. Returns Pass on success.
##########################################################################

sub IsCorrectFieldNameInArray ()
{
    my ($exp, $act) = @_;

    my ($test) = "Pass";

    $exp = $exp->{SON};
    while($exp)
    {
        if($exp->{FIELD_NAME} eq "PIN_FLD_NAME")
        {
            $act = $act->{SON};
            while($act)
            {
                if($act->{FIELD_NAME} eq "PIN_FLD_NAME")
                {
                    my $expval = $exp->{VALUE};
                    $expval =~ s/^\[\d+\]\s*(.*)\s*$/$1/;
                    ## To remove quotes (") on the borders.
                    $expval =~ s/^\s*"\s*//g;
                    $expval =~ s/\s*"\s*$//g;

                    my $actval = $act->{VALUE};
                    $actval =~ s/^\[\d+\]\s*(.*)\s*$/$1/;
                    ## To remove quotes (") on the borders.
                    $actval =~ s/^\s*"\s*//g;
                    $actval =~ s/\s*"\s*$//g;

                    $test = "Fail" if($expval ne $actval);
                    last;   
                }
                $act = $act->{NEXT};
            }
            last;
        }
        $exp = $exp->{NEXT};
    }
    return $test;
}

##########################################################################
# Subroutne   : IsCorrectPoidMatch
# Description : This subroutine checks that if an array has PIN_FLD_POID,
#               then it matches with the PIN_FLD_POID field which has same
#               storable class and DB no. Returns Pass on success.
##########################################################################

sub IsCorrectPoidMatch ()
{
    my ($exp, $act) = @_;

    my ($test) = "Pass";

    $exp = $exp->{SON};
    while($exp)
    {
        if($exp->{FIELD_NAME} eq "PIN_FLD_POID")
        {
            $act = $act->{SON};
            while($act)
            {
                if($act->{FIELD_NAME} eq "PIN_FLD_POID")
                {
                    $test = 
                       IsSameStorableClass($exp->{VALUE}, $act->{VALUE});
                    last;
                }
                $act = $act->{NEXT};
            }
            last;
        }
        $exp = $exp->{NEXT};
    }
    return $test;
}

##########################################################################
# Subroutne   : IsCorrectResourceIdMatch
# Description : This subroutine checks the resorce id in the PIN_FLD_BALANCES
#               arrays for expected and actual. Returns Pass, if they match
#               otherwise it returns Fail.
##########################################################################

sub IsCorrectResourceIdMatch ()
{
    my ($exp, $act) = @_;
    my ($test) = "Pass";

    $exp->{VALUE} =~ m/^\[(\d+)\]\s*.*\s*$/;
    my $exp_resource_id = $1;

    $act->{VALUE} =~ m/^\[(\d+)\]\s*.*\s*$/;
    my $act_resource_id = $1;

    $test = "Fail" if($exp_resource_id != $act_resource_id);

    return $test;
}

##########################################################################
# Subroutne   : validPassCount
# Description : return the number of valid passes for an array elements.
##########################################################################

sub validPassCount ()
{
    my ($self) = shift;

    my ($count) = 0;
    my $temp = $self->{SON};
    while(defined $temp)
    {
        if((defined $temp->{VALID_FLAG}) and
           ((($temp->{VALID_FLAG} eq "TRUE") and ($temp->{STATUS} eq "MATCH_PASSED")) or 
           (($temp->{VALID_FLAG} eq "FALSE") and ($temp->{STATUS} ne "MATCH_PASSED")) or 
           (($temp->{VALID_FLAG} eq "ABSENT") and ($temp->{STATUS} eq "NOT_FOUND"))))
        {
            $count++;
        }
        $temp = $temp->{NEXT};
        
    }
    return $count;
}

##########################################################################
# Subroutne   : IsSameStorableClass
# Description : Returns "Pass" if same storable class, "Fail" otherwise.
##########################################################################

sub IsSameStorableClass ()
{
    my ($expval, $actval) = @_;
    my ($test) = "Pass";

    $expval =~ s/^\[\d+\]\s*(.*)\s*$/$1/;
    ## To remove quotes (") on the borders.
    $expval =~ s/^\s*"\s*//g;
    $expval =~ s/\s*"\s*$//g;

    $actval =~ s/^\[\d+\]\s*(.*)\s*$/$1/;
    ## To remove quotes (") on the borders.
    $actval =~ s/^\s*"\s*//g;
    $actval =~ s/\s*"\s*$//g;

    my @expval = split(/\s+/, $expval);
    my $exp_db_no = $expval[0];
    my $exp_storable = $expval[1];

    my @actval = split(/\s+/, $actval);
    my $act_db_no = $actval[0];
    my $act_storable = $actval[1];

    if(($exp_storable ne $act_storable) or
      ($exp_db_no ne $act_db_no))
    {
        $test = "Fail";
    }
    if (($exp_db_no eq $act_db_no) and
        ($exp_storable =~ /payinfo/))
    {
        $test = "Pass";
    }
    return $test;
}
################################################################################
# Subroutine    : printHeader
# Description   : prints the header for the detailed report
################################################################################
sub printHeader
{
    local (*LOGFILE) = shift;
    # Print header
    printf(LOGFILE "%-27s|%-9s|%-37s|%-37s|%-6s\n",
                   "Field Name", "Data Type", "Expected Value",
                   "Actual Value", "Status");
    print LOGFILE "=" x120, "\n";

}

##########################################################################
# Subroutne   : newPrint
# Description : This routine writes in the .out file. This routine is to
#               make the display compatible with the old style of printing.
##########################################################################

sub newPrint()
{
    my ($self) = shift;
    local (*LOGFILE) = shift;

    ##################################################
    # Total 30 + 40 + 40 + 6 + (4 | chars) = 120 chars
    ##################################################
    my $level ="" ;
    $level = $self->{NESTING_LEVEL}
                 if(defined $self->{NESTING_LEVEL});
    my $fldName ="" ; 
    $fldName  = $self->{FIELD_NAME}
                 if(defined $self->{FIELD_NAME});

    $fldName = $level. " "."  " x $level. $fldName;
    $fldName  = &formatField ($fldName, 27);

    my $dataType ="";
    $dataType  = &formatField ($self->{DATA_TYPE}, 9)
                 if(defined $self->{DATA_TYPE});
    my $expVal = "";
    $expVal = &formatField ($self->{VALUE}, 37)
                 if(defined $self->{VALUE});
    my $actVal = "";
    $actVal = &formatField ($self->{ACTUAL}->{VALUE}, 37)
                 if(defined $self->{ACTUAL}->{VALUE});
    my $status = "";
    $status = &formatField ($self->{STATUS}, 5)
                 if(defined $self->{STATUS});
    my $VFLAG = "";
    $VFLAG = "Valid" if ((defined $self->{VALID_FLAG}) and
                         ($self->{VALID_FLAG} eq "TRUE"));
    $VFLAG = "VFail" if ((defined $self->{VALID_FLAG}) and
                         ($self->{VALID_FLAG} eq "FALSE"));
    $VFLAG = "VField" if ((defined $self->{VALID_FLAG}) and
                         ($self->{VALID_FLAG} eq "FIELDNAME"));
    $VFLAG = "VAbsent" if ((defined $self->{VALID_FLAG}) and
                         ($self->{VALID_FLAG} eq "ABSENT"));
    my $expline = "";
    $expline = $self->{LINE_NUM}
                  if(defined $self->{LINE_NUM});
    my $actline = "";
    $actline = $self->{ACTUAL}->{LINE_NUM}
                  if(defined $self->{ACTUAL}->{LINE_NUM});
    my $MARK = "";
    $MARK = $self->{MARK}
                  if(defined $self->{MARK});

    printf(LOGFILE "%-27s|%-9s|%-37s|%-37s|%-5s|%-5s %s\n",
                 $fldName, $dataType, $expVal, $actVal, $status, $VFLAG,
                ($showlinenum ? "$expline,$actline"."$MARK" :"$MARK"));

    if(defined $self->{SON}) { $self->{SON}->newPrint(*LOGFILE); }

    if(defined $self->{NEXT}) { $self->{NEXT}->newPrint(*LOGFILE); }
}

################################################################################
# Subroutine    : printFooter
# Description   : prints the footer for the detailed report
################################################################################
sub printFooter
{
    local (*LOGFILE) = shift;
    # Print footer
    print LOGFILE "=" x120, "\n";

}

################################################################################
# Subroutine    : formatField
# Description   : formats the fields
################################################################################

sub formatField
{
    my ($tmpfld, $len) = @_;
    chomp ($tmpfld);
    my ($field) = ();

    if ( (length ($tmpfld)) >= $len ) 
    {
        $field = substr ($tmpfld, 0, $len);
    } 
    else
    {
        $field = $tmpfld;
    }
    return $field;
}

##########################################################################
# Subroutne   : replaceVariableValues
# Description : This routine replaces the variables values before
#               them in matching table.
##########################################################################

sub replaceVariableValues ()
{
    my ($self) = shift;

    if((defined $self->{VALUE}) and
       ($self->{VALUE} =~ /^(.*)(%var\d+)(.*)$/))
    {
        if(defined $variables{$2})
        {
            $self->{VALUE} =  $1.$variables{$2}.$3
        }

    }
        
    if(defined $self->{SON}) { $self->{SON}->replaceVariableValues(); }

    if(defined $self->{NEXT}) { $self->{NEXT}->replaceVariableValues(); }

}

##########################################################################
# Subroutne   : addMissingFieldsInTree
# Description : This routine adds all the missing fields in expected tree.
##########################################################################

sub addMissingFieldsInTree ()
{
    my ($self) = @_;

    if((! defined $self->{STATUS}) and
       (defined $self->{PREV}->{EXPECTED}))
    {
        my $expnode = $self->{PREV}->{EXPECTED};
        $expnode->createMissingExpectedNode($self);
    }

    $self->{SON}->addMissingFieldsInTree() if(defined $self->{SON});

    $self->{NEXT}->addMissingFieldsInTree() if(defined $self->{NEXT});

    return;
}

##########################################################################
# Subroutne   : createMissingExpectedNode
# Description : This routine creates and inserts a missing node.
##########################################################################

sub createMissingExpectedNode()
{
    my ($self) = shift;
    my ($actual) = shift;

    my($node) = {};
    $node->{NESTING_LEVEL} = $actual->{NESTING_LEVEL};
    $node->{DATA_TYPE} = $actual->{DATA_TYPE};
    $node->{FIELD_NAME} = $actual->{FIELD_NAME};
    $node->{VALUE} = "         << Missing field >>";
    $node->{ACTUAL} = $actual;
    $node->{STATUS} = "Warn";
    $node->{PREV} = $self;

    #######################################
    # Enforce validation for PIN_FLD_ERR_BUF
    #######################################
    
    if($actual->{FIELD_NAME} =~ /PIN_FLD_ERR_BUF/)
    {
        $node->{VALID_FLAG} = "TRUE";
        $node->{STATUS} = "Fail";
    }

    ######################
    # Bless this refrence.
    ######################

    $node = Comparator->treeNode($node);

    ##############################
    # Get the place to attach this
    # node in expected tree.
    ##############################

    if(defined $self->{SON})
    {
        my $temp = $self->{SON};
        while($temp->{NEXT})
        {
            $temp = $temp->{NEXT};
        }
        $temp->{NEXT} = $node;
    }
    else
    {
        $self->{SON} = $node;
    }
    $actual->{EXPECTED} = $node;

    return;
}

##########################################################################
# Subroutne   : createMissingElemInArray
# Description : This function creates the missing elements before
#               any matching is done.
##########################################################################

sub resetExpectArrayOrSubstruct()
{
    my ($array) = shift;

    my $temp = $array->{SON};
    while($temp)
    {
        if(!(($temp->{DATA_TYPE} eq "ARRAY") or
            ($temp->{DATA_TYPE} eq "SUBSTRUCT")))
        {
            $temp->createMissingActualNode();
            $temp->{STATUS} = "NOT_FOUND";
        }
        $temp = $temp->{NEXT};
    }
    return;
}

##########################################################################
# Subroutne   : createMissingActualNode
# Description : This routine creates and inserts a missing node.
##########################################################################

sub createMissingActualNode()
{
    my ($self) = shift;

    my($node) = {};
    $node->{NESTING_LEVEL} = $self->{NESTING_LEVEL};
    $node->{DATA_TYPE} = $self->{DATA_TYPE};
    $node->{FIELD_NAME} = $self->{FIELD_NAME};
    $node->{VALUE} = "         << Missing field >>";

    ######################
    # Bless this refrence.
    ######################

    $node = Comparator->treeNode($node);

    $self->{ACTUAL} = $node;

    return;
}

##########################################################################
# Subroutne   : doNormAct
# Description : This routine does normalization on expected and actual
#               field values.
##########################################################################

sub doNormAct ()
{
    my ($normalizeexp,$normalizeact,$normfield,$normftype) = @_;

    my ($normalizename,$didnormexp,$didnormact,
        @normret,$lastnormexp,$lastnormact, $normsub);

    $lastnormexp=$normalizeexp;
    $lastnormact=$normalizeact;

    my $normact = &getNormHashRef;

    ###################################################################
    #might have to split into exp/act this in future or pass to normsub
    #hm! specific field before generic, or visyversy?
    #well, "ALLFLD" was already first, so let's do it this way for now:
    ###################################################################

    foreach my $curnormfield( "ALLFLD", $normftype, $normfield )
    {

        foreach $normalizename( sort keys %{$$normact{$curnormfield}})
        {
            $normsub=$$normact{$curnormfield}{$normalizename};
            @normret=&$normsub($normalizeexp,$normalizeact);
            if( @normret eq 2 )
            {
                ($normalizeexp,$normalizeact) = @normret;
            }
        }
    }
    ($normalizeexp,$normalizeact);
}

##########################################################################
# Subroutne   : matchFromBottomToTop
# Description : This matches two trees starting bottom to top.
##########################################################################

sub matchFromBottomToTop()
{
    my ($expref, $actref, $exp_flist) = @_;

    local ($MAX_LEVEL) = -1;

    $expref->GetMaximumLevel(*MAX_LEVEL);

    local *DEBUG = getDebugFileHandle() if($debug);

    $level = $MAX_LEVEL - 1;

    ############################################
    # Going beyond 2 may give incorrect results.
    ############################################
    $level = 2 if($level > 2);

    while($level >= 0)
    {
        local(@actlist, @explist);

        $expref->getArraysOrSubstruct($level, *explist);
        $actref->getArraysOrSubstruct($level, *actlist);

        local(@grexplist, @gractlist);

        $expref->groupArrays(*explist, *grexplist);
        $actref->groupArrays(*actlist, *gractlist);

        if($debug)
        {
            print  DEBUG "\n Expected Grouped arrays at level : $level\n\n";
            foreach my $arrayref (@grexplist)
            {
                print DEBUG "\n\nGROUP:\n";
                foreach my $arrayref1 (@$arrayref)
                {
                    $arrayref1->printArrayElements(*DEBUG);
                    print DEBUG "\n";
                }
            }

            print  DEBUG "\n Actual Grouped arrays at level : $level\n\n";
            foreach my $arrayref (@gractlist)
            {
                print DEBUG "\n\nGROUP:\n";
                foreach my $arrayref1 (@$arrayref)
                {
                    $arrayref1->printArrayElements(*DEBUG);
                    print DEBUG "\n";
                }
            }
        }
        #####################################
        # Match grouped array lists. FINALLY
        #####################################

        matchGroupedArrayList(*grexplist, *gractlist);

        $level--;
    }    

    if(!defined $expref->{STATUS})
    {
        local(@grexplist, @gractlist);

        my $exp_root = [$expref];
        my $act_root = [$actref];

        &matchTwoGroupedArrays($exp_root, $act_root);
    }

    if($debug)
    {
        print DEBUG "\n##########################################\n";
        print DEBUG "# Expected Flist dump after matching is over:";
        print DEBUG "\n##########################################\n\n";
        $expref->{SON}->dumpFlistStringFromFlistTree(*DEBUG)
                                    if(defined $expref->{SON});
        print DEBUG "\n##########################################\n";
        print DEBUG "# Actual Flist dump after matching is over:";
        print DEBUG "\n##########################################\n\n";
        $actref->{SON}->dumpFlistStringFromFlistTree(*DEBUG)
                                    if(defined $actref->{SON});
    }


    return;
}

##########################################################################
# Subroutne : getArraysOrSubstruct
# Description : This gets all the array refrences at maximum level.
#               These array  elements will be  grouped based on same father.
##########################################################################

sub getArraysOrSubstruct()
{
    my ($self) = shift;
    my ($level) = shift;
    local (*list) = shift;

    if(($self->{NESTING_LEVEL} == $level) and
       ($self->{DATA_TYPE} =~ /(ARRAY|SUBSTRUCT)/) and
       (!defined $self->{STATUS}))
    {
        $list[$#list+1] = $self;
    }
    if(defined $self->{SON}) {$self->{SON}->getArraysOrSubstruct($level, *list); }

    if(defined $self->{NEXT}) { $self->{NEXT}->getArraysOrSubstruct($level, *list); }

}

##########################################################################
# Subroutne   : groupArrays
# Description : This subroutine groups a list of arrays based on
#                same parent. This grouping is important since we
#                have to make necessary arrangements that same set of
#                arrays should be matched in actual and expected list.
#
#                Finally a hash will be generated for which key will be
#                the parent's field name.
#
#                Moral of the story is that we have to match such hashes
#                for actual and expected trees at each level.
###########################################################################

sub groupArrays()
{
    my ($self) = shift;
    local (*ungroupedlist, *groupedlist) = @_;
    if( @ungroupedlist)
    {
        my @temp = ();
        my ($i) = 0;
        push(@temp, $ungroupedlist[$i]); ###push the first element in the temp array.
        while($i < $#ungroupedlist)
        {
            if($ungroupedlist[$i]->{PREV} == $ungroupedlist[$i+1]->{PREV}) # Same parent so group them.
            {
               push(@temp, $ungroupedlist[$i+1]);
            }
            else
            {
                $groupedlist[$#groupedlist+1] = [@temp];
                @temp = ();                            #Start a different group.
                push(@temp, $ungroupedlist[$i+1]);
            }
            $i++;
        }
        #### The last group should not be left.

        $groupedlist[$#groupedlist+1] = [@temp];
    }
    return;
}

##########################################################################
# Subroutne   : matchGroupedArrayList
# Description : This subroutine matches the expected and actual grouped
#                array lists.
##########################################################################

sub matchGroupedArrayList()
{
    local (*explist, *actlist) = @_;

    my ($prev_score ) = ();
    my ($prevgroup ) = ();

    ###########################
    #Start Matching two lists.
    ###########################

    foreach my $expgroup (@explist)
    {
         my $exp_path = "";
         $exp_path = $expgroup->[0]->getParentPath() if(@$expgroup);

         foreach my $actgroup (@actlist)
         {
             if(! defined $actgroup)
             {
                 next;
             }

             my $act_path = "";
             $act_path = $actgroup->[0]->getParentPath() if(@$actgroup);

             #####################################
             # If parent path's are not equal take
             # next array group.
             #####################################

             if($exp_path ne $act_path)
             {
                 next;
             }

             #########################################
             # If the number of arrays in the expected
             # group is greater than the number of arrays
             # in actual group, take next
             #####################################

             my $MAX_SCORE = getGroupScore($expgroup, 1);

            ######################################
            # Now we have two array groups we need
            # to perform match on this. But clean
            # everything before doing this.
            ######################################
            resetArrayStatus1($expgroup);
            resetArrayStatus1($actgroup);
            resetArrayStatus1($prevgroup);

            &matchTwoGroupedArrays($expgroup, $actgroup);

            ##################
            # Check the score.
            ##################

            my $score = getGroupScore($expgroup, 0);

            if( $score >= $MAX_SCORE)
            {
                $prevgroup = $actgroup;
                last;
            }
            elsif ( ( defined $prev_score) and ($prev_score > $score) )
            {
                #######################################
                # Set all the previous refrences again.
                # Before that clean up everything.
                #######################################
                resetArrayStatus1($expgroup);
                resetArrayStatus1($actgroup);
                resetArrayStatus1($prevgroup);

                &matchTwoGroupedArrays($expgroup, $prevgroup);
            }
            else
            {
                $prev_score = $score;
                $prevgroup = $actgroup;
            }
        }
        ###########################################
        # The below block is to match parent elems.
        ###########################################

        my $exp_parent =$expgroup->[0]->{PREV};
        my $act_parent =$prevgroup->[0]->{PREV};
        while(defined $exp_parent)
        {
            if(!defined $exp_parent->{STATUS})
            {
                $exp_parent->matchArrayOrSubstructElements($act_parent);
                matchValues($exp_parent, $act_parent);
                $act_parent->{STATUS} = "MATCH_DONE";
            }
            $exp_parent = $exp_parent->{PREV};
            $act_parent = $act_parent->{PREV};
        }
        #############################################
        # The following group is to match child elms.
        #############################################

        foreach my $exparray (@$expgroup)
        {
                my $actarray = $exparray->{ACTUAL};
                my @expgr = ();
                my @actgr = ();
                my $exp = $exparray->{SON};
                while(defined $exp)
                {
                    if(($exp->{DATA_TYPE} eq "ARRAY") or
                      ($exp->{DATA_TYPE} eq "SUBSTRUCT"))
                    {
                        push(@expgr, $exp);
                    }
                    $exp = $exp->{NEXT};
                }
                my $act = $actarray->{SON};
                while(defined $act)
                {
                    if(($act->{DATA_TYPE} eq "ARRAY") or
                       ($act->{DATA_TYPE} eq "SUBSTRUCT"))
                    {
                        push(@actgr, $act);
                    }
                    $act = $act->{NEXT};
                }
                local @child_exp = ([@expgr]);
                local @child_act = ([@actgr]);
                &matchGroupedArrayList(*child_exp, *child_act)
                                                       if(@expgr);
        }
        foreach my $actgroup (@actlist)
        {
            if(( defined $actgroup ) and ( defined $prevgroup) and
               ( $actgroup == $prevgroup))
            {
                $actgroup = ();
                last;
            }
        }
        $prev_score = ();
        $prevgroup = ();
    }
    return;
}

##########################################################################
# Subroutne   : getParentPath()
# Description : This returns the path string for that node.
#               Path string is something like
#                    ROOT:PIN_FLD_ABC:PIN_FLD_XYZ:.....
##########################################################################

sub getParentPath ()
{
    my ($self) = @_;

    my $ref = $self->{PREV};

    my $path_string = "";
    if(defined $ref)
    {
        while($ref->{FIELD_NAME} ne "PIN_FLD_ROOT_NODE")
        {
            $path_string = $ref->{FIELD_NAME}.":".$path_string;
            $ref=$ref->{PREV};
        }
        $path_string="ROOT:".$path_string;
    }
    return $path_string;
}

##########################################################################
# Subroutne : GetMaximumLevel
# Description : This returns the maximum level of an flist.
##########################################################################

sub GetMaximumLevel()
{
    my ($self) = shift;
    local (*MAX_LEVEL) = shift;

    if((defined $self->{NESTING_LEVEL}) and
       ($self->{NESTING_LEVEL} > $MAX_LEVEL))
    {
        $MAX_LEVEL = $self->{NESTING_LEVEL};
    }

    if(defined $self->{SON}) { $self->{SON}->GetMaximumLevel(*MAX_LEVEL); }

    if(defined $self->{NEXT}) { $self->{NEXT}->GetMaximumLevel(*MAX_LEVEL); }

}

##########################################################################
# Subroutne   : resetArrayStatus1
# Description : This function clears the status info from a subroutine.
##########################################################################

sub resetArrayStatus1()
{
    my ($group) = shift;

    foreach my $array(@$group)
    {
        $array->{STATUS} = ()
             if(defined $array->{STATUS});
        $array->{ACTUAL} = ()
             if(defined $array->{ACTUAL});
        $array->{EXPECTED} = ()
             if(defined $array->{EXPECTED});
        my $temp = $array->{SON};
        while($temp)
        {
            if(!(($temp->{DATA_TYPE} eq "ARRAY") or
                ($temp->{DATA_TYPE} eq "SUBSTRUCT")))
            {
                $temp->{STATUS} = ()
                     if(defined $temp->{STATUS});
                $temp->{ACTUAL} = ()
                     if(defined $temp->{ACTUAL});
                $temp->{EXPECTED} = ()
                     if(defined $array->{EXPECTED});
            }
            $temp = $temp->{NEXT};
        }
    }
    return;
}
##########################################################################
# Subroutne   : getGroupScore
# Description : This subroutine returns the maximum score.
##########################################################################

sub getGroupScore ()
{
    my $group = shift;
    my $flag = shift;
    my $score = 0;

    foreach my $array(@$group)
    {
    my $temp=$array->{SON};
    while(defined $temp)
    {
        if(!(($temp->{DATA_TYPE} eq "ARRAY") or
            ($temp->{DATA_TYPE} eq "SUBSTRUCT")))
        {
            if($flag == 0)
            {
                if((defined $temp->{STATUS}) and
                   ($temp->{STATUS}  eq "MATCH_PASSED"))
                {
                    $score++;
                }
            }
            else
            {
                $score++;
            }
        }
        $temp=$temp->{NEXT};
    }
    }
    return $score;
}

##########################################################################
# Subroutne : printArrayElements
# Description : This prints all the array elements.
##########################################################################

sub printArrayElements ()
{

     my ($self) = shift;
     local *LOGFILE  = shift;

     if($self)
     {
         print LOGFILE "$self->{NESTING_LEVEL}",
           "  " x $self->{NESTING_LEVEL},
           " $self->{FIELD_NAME}", "\t\t",
           "$self->{DATA_TYPE} $self->{VALUE}\n";
     }

     if($self->{SON})
     {
         $self = $self->{SON};
         print LOGFILE "$self->{NESTING_LEVEL}",
           "  " x $self->{NESTING_LEVEL},
           " $self->{FIELD_NAME}", "\t\t",
           "$self->{DATA_TYPE} $self->{VALUE}\n";
     }
     else
     {
         return;
     }

     while($self->{NEXT})
     {
         $self = $self->{NEXT};

         print LOGFILE "$self->{NESTING_LEVEL}",
           "  " x $self->{NESTING_LEVEL},
           " $self->{FIELD_NAME}", "\t\t",
           "$self->{DATA_TYPE} $self->{VALUE}\n";
     }
     return;
}


##########################################################################
# We provide a DESTROY method so that the autoloader
# doesn't bother trying to find it.
##########################################################################

sub DESTROY { }


1;  # To ensure that last statement evaluates to be true.


__END__

#####################################################################
# Future things:
# -------------
# 1) If there is problem of hierarchy like level increases without having
#    a previous ARRAY or SUBSTRUCT element. Handle it properly.
# 2) Give a user to validate by field option.
#####################################################################
