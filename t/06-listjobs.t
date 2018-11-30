#!perl
use 5.006;
use strict;
use warnings;
use Test::More qw(no_plan);
use Win32::Backup::Robocopy;
use File::Path qw( make_path remove_tree );

my $tbasedir = File::Spec->catdir(File::Spec->tmpdir(),'test_backup');
note("creating a backup scenario  in $tbasedir");
make_path( $tbasedir );


my $bkp = Win32::Backup::Robocopy->new( conf =>  File::Spec->catfile($tbasedir,'test_backup') );

ok (0 == scalar $bkp->listjobs, 'zero returned in scalar context if no jobs are configured');

$bkp->job(name=>'job1',src=>'.',cron=>'5 * * 1 *',history=>1);
$bkp->job(name=>'job2',src=>'.',cron=>'3 * * 4 *',history=>1);

ok( 2 == scalar $bkp->listjobs(),'correct number of elements in scalar context' );

my @arr = $bkp->listjobs();
ok( 2 == @arr,'correct number of elements in list context' );

foreach my $ele ( @arr ){
	ok( $ele =~ /name = job\d src =.*files =.*cron =.*next_time_descr =.*/,'correct output in list context');
}

# remove the backup scenario
note("removing bakup scenario in $tbasedir");
remove_tree($tbasedir);