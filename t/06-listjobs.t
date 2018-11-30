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

# new in JOB mode just needs conf croaks if destination drive does not exists
my $bkp = Win32::Backup::Robocopy->new( conf =>  File::Spec->catfile($tbasedir,'test_backup') );

$bkp->job(name=>'job1',src=>'.',cron=>'5 * * 1 *',history=>1);
$bkp->job(name=>'job2',src=>'.',cron=>'3 * * 4 *',history=>1);

print "config has ",scalar $bkp->listjobs," jobs\n";

print join "\n",$bkp->listjobs();
print "\n\n";
print join "\n",$bkp->listjobs(format=>'compact',fields=>[qw(name files cron next_time_descr)]);
print "\n\n";
print join "\n",$bkp->listjobs(format=>'long',fields=>[qw(name src dst files cron next_time_descr)]);
print "\n\n";


ok( 2 == scalar $bkp->listjobs(),'correct number of elements in scalar context' );

my @arr = $bkp->listjobs();
ok( 2 == @arr,'correct number of elements in list context' );

foreach my $ele ( @arr ){
	ok( $ele =~ /name = job\d src =.*files =.*cron =.*next_time_descr =.*/,'correct output in list context');
}

# remove the backup scenario
note("removing bakup scenario in $tbasedir");
remove_tree($tbasedir);