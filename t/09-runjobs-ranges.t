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
my $conf = File::Spec->catfile($tbasedir, 'my_config.json');
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

# add a serie of job identical
$bkp->job(  name => 'test0', src => $tsrc, dst => $tdst, verbose => 1,
			cron => '0 0 25 12 *', first_time_run => 1);
$bkp->job(  name => 'test1', src => $tsrc, dst => $tdst, verbose => 1,
			cron => '0 0 25 12 *', first_time_run => 1);
$bkp->job(  name => 'test2', src => $tsrc, dst => $tdst, verbose => 1,
			cron => '0 0 25 12 *', first_time_run => 1);
$bkp->job(  name => 'test3', src => $tsrc, dst => $tdst, verbose => 1,
			cron => '0 0 25 12 *', first_time_run => 1);
$bkp->job(  name => 'test4', src => $tsrc, dst => $tdst, verbose => 1,
			cron => '0 0 25 12 *', first_time_run => 1);
$bkp->job(  name => 'test5', src => $tsrc, dst => $tdst, verbose => 1,
			cron => '0 0 25 12 *', first_time_run => 1);

			
# running only job number 3 
my ($stdout, $stderr, @result) = capture { $bkp->runjobs(3) };
my @lines = split '\n',$stdout;
ok($lines[0] eq 'considering job [test3]','right job considered in verbose mode');
ok($lines[1] eq 'executing job [test3]','right job executed');


# run only jobs 0,2,3
# NB runjobs accepts both STRING and ARRAY
($stdout, $stderr, @result) = capture { $bkp->runjobs(0,2..3) };

@lines = split '\n',$stdout;

ok($lines[0] eq 'considering job [test0]','considered [test0]');
ok($lines[1] eq 'executing job [test0]','executed [test0]');
ok($lines[2] =~ /^mkdir.*test0$/,'mkdir for test0');
ok($lines[3] eq 'considering job [test2]','considered [test2]');
ok($lines[4] eq 'executing job [test2]','executed [test2]');
ok($lines[5] =~ /^mkdir.*test2$/,'mkdir for test2');
ok($lines[6] eq 'considering job [test3]','considered [test3]');
ok($lines[7] =~ /^is not time to execute \[test3\].*00:00:00/,'not time for [test3]');

# run all jobs just to trigger them
($stdout, $stderr, @result) = capture { $bkp->runjobs() };

# check array range work as expected				=> 0,1,2
($stdout, $stderr, @result) = capture { $bkp->runjobs(0..2,1) };
@lines = split '\n',$stdout;
ok($lines[0] eq 'considering job [test0]','considered [test0]');
ok($lines[1] =~ /^is not time to execute \[test0\]/,'not time for [test0]');
ok($lines[2] eq 'considering job [test1]','considered [test1]');
ok($lines[3] =~ /^is not time to execute \[test1\]/,'not time for [test1]');
ok($lines[4] eq 'considering job [test2]','considered [test2]');
ok($lines[5] =~ /^is not time to execute \[test2\]/,'not time for [test2]');

# check array range work as expected				=> 0,1,5
($stdout, $stderr, @result) = capture { $bkp->runjobs(5,0..1) };
@lines = split '\n',$stdout;
ok($lines[0] eq 'considering job [test0]','considered [test0]');
ok($lines[1] =~ /^is not time to execute \[test0\]/,'not time for [test0]');
ok($lines[2] eq 'considering job [test1]','considered [test1]');
ok($lines[3] =~ /^is not time to execute \[test1\]/,'not time for [test1]');
ok($lines[4] eq 'considering job [test5]','considered [test5]');
ok($lines[5] =~ /^is not time to execute \[test5\]/,'not time for [test5]');

# dies with invalid ranges array
# CAVEAT: 4..0 result into an empty @_ which will mean ALL jobs!
# $bkp->runjobs(4..0);
# dies_ok {  $bkp->runjobs(4..0) } "invalid reverse range [4..0]";


# remove the backup scenario
note("removing bakup scenario in $tbasedir");
remove_tree($tbasedir);

