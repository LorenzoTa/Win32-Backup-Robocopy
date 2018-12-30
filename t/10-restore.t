#!perl
use 5.006;
use strict;
use warnings;
use Test::More;
use Test::Exception;
use Win32::File qw(:DEFAULT GetAttributes SetAttributes);
use Win32::Backup::Robocopy;

use lib '.';
use t::bkpscenario;

plan tests => 1;

#######################################################################
# a real minimal bkp scenario
#######################################################################
my ($tbasedir,$tsrc,$tdst) = bkpscenario::create_dirs();
BAIL_OUT( "unable to create temporary folders!" ) unless $tbasedir;
note("created bakup scenario in $tbasedir");

my $file1 = 'Foscolo_A_Zacinto.txt';
my $tfh1 = bkpscenario::open_file($tsrc,$file1);
BAIL_OUT( "unable to create temporary file!" ) unless $tfh1;

bkpscenario::update_file($tfh1,0);			

# a backup without history
my $bkp = Win32::Backup::Robocopy->new(
	name => 'test',
	source	 => $tsrc,
	dst => $tdst,	
);

# check parameters passed to restore call
dies_ok { $bkp->restore() } 
	"restore is expected to die without parameters";

dies_ok { $bkp->restore( to => $tsrc ) } 
	"restore is expected to die without 'from' parameter";

dies_ok { $bkp->restore( from => $tdst ) } 
	"restore is expected to die without 'to' parameter";

dies_ok { $bkp->restore( from => File::Spec->catdir ( Win32::GetNextAvailDrive(),'' )) } 
	"restore is expected to die if 'from' does not exists";

# a valid backup
$bkp->run;

# a valid restore
my ($stdout, $stderr, $exit, $exitstr) = $bkp->restore( 
											from => File::Spec->catdir ( $tdst,'test' ), 
											to => $tbasedir 
);
ok ( $exit < 8, "first restore completed succesfully" );

# update the file in source
$tfh1 = bkpscenario::open_file($tsrc,$file1);
BAIL_OUT( "unable to create temporary file!" ) unless $tfh1;
bkpscenario::update_file($tfh1,1);	

# a valid backup again
$bkp->run;
# a valid restore again
($stdout, $stderr, $exit, $exitstr) = $bkp->restore( 
											from => File::Spec->catdir ( $tdst,'test' ), 
											to => $tbasedir 
);
ok ( $exit < 8, "second restore completed succesfully" );







