#!perl
use 5.006;
use strict;
use warnings;
use Test::More qw(no_plan);
use Test::Exception;
use File::Path qw( make_path remove_tree );
use Capture::Tiny qw(capture);
use Win32::Backup::Robocopy;


#######################################################################
# a real minimal bkp scenario
#######################################################################
my $tbasedir = File::Spec->catdir(File::Spec->tmpdir(),'test_backup');
note("creating a bakup scenario in $tbasedir");
my $tsrc = File::Spec->catdir( $tbasedir,'src');
my $tdst = File::Spec->catdir( $tbasedir,'dst');
foreach  my $dir ($tbasedir,$tsrc,$tdst){
		unless (-d $dir){ make_path( $dir ) }
		BAIL_OUT( "unable to create temporary folder: [$dir]!" ) unless -d $dir;
}
my $conf = File::Spec->catfile($tbasedir,'my_config.json');
my $filename = 'Foscolo_A_Zacinto.txt';
my $file1 = File::Spec->catfile($tsrc, $filename);
open my $tfh1, '>', $file1 or BAIL_OUT ("unable to write $file1 in $tsrc!");
print $tfh1 "\t\tA ZACINTO\n\n",
			"Né più mai toccherò le sacre sponde\n",
			"  ove il mio corpo fanciulletto giacque,\n",
			"  Zacinto mia, che te specchi nell'onde\n",
			"  del greco mar da cui vergine nacque\n";
			
close $tfh1 or BAIL_OUT ("impossible to close $file1");
#######################################################################
# end of minimal bkp scenario 
#######################################################################

# a bkp in a job mode
my $bkp = Win32::Backup::Robocopy->new( config => $conf );

# add a job  with first_time_run=>1
$bkp->job(  name => 'test3', src => $tsrc, dst => $tdst,
			cron => '0 0 25 12 *', first_time_run => 1);

# this time it must return executing job [name]
my ($stdout, $stderr, @result) = capture { $bkp->runjobs() };
like( $stdout, qr/^executing job \[test3\]/, "right output of first_time_run (executing..)");

# now it must says it's not time to run: first_time_run run only once!
($stdout, $stderr, @result) = capture { $bkp->runjobs() };
like( $stdout, qr/^is not time to execute/, "right output of first_time_run (skipping..)");

undef $bkp;
$bkp = Win32::Backup::Robocopy->new( config => 'my_config.json' );
# same source different dest and second with history
$bkp->job(	name=>'test3',src=>$tsrc,
			dst=>$tdst,cron=>'0 0 25 1 *',
			history=>0,first_time_run => 1);
			
$bkp->job(	name=>'test4',src=>$tsrc,
			dst=>$tdst,cron=>'0 0 25 1 *',
			history=>1,first_time_run => 1);

($stdout, $stderr, @result) = capture { $bkp->runjobs() };

# inside test3 must be a file
ok(-e File::Spec->catfile($tdst,'test3','Foscolo_A_Zacinto.txt'),'file exists in  directory test3');

# get the position of last HISTORY backup
opendir my $lastdir, File::Spec->catdir($tdst,'test4') or BAIL_OUT ("Unble to read directory test4!");
my @ordered_dirs = sort grep {!/^\./} readdir($lastdir);
my $lastfilepath = File::Spec->catfile( $bkp->{dst}, $ordered_dirs[-1], $filename);

ok( ! -e File::Spec->catfile($tdst,'test4','Foscolo_A_Zacinto.txt'),'file does not exists in  directory test4');

# remove the backup scenario
note("removing bakup scenario in $tbasedir");
remove_tree($tbasedir);
