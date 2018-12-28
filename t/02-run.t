#!perl
use 5.006;
use strict;
use warnings;
use Test::More;
use Test::Exception;
use File::Path qw( make_path remove_tree );
use Win32::File qw(:DEFAULT GetAttributes SetAttributes);
use Win32::Backup::Robocopy;

plan tests => 12;

# run croaks if destination drive does not exists
my $nobkp = Win32::Backup::Robocopy->new( 
	name => 'impossible',
	src	 => '.',
	dst => File::Spec->catdir ( Win32::GetNextAvailDrive(),'' )
);
dies_ok { $nobkp->run } 'run is expected to die with no existing destination drive';

# run croaks if invalid name was given for destination
$nobkp = Win32::Backup::Robocopy->new( 
	name => 'impos??????sible',
	verbose => 1,
	src	 => '.',
	dst => '.', 
);
dies_ok { $nobkp->run } 'run is expected to die with invalid folder name';

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

# check $exit code: now has to be 1 as for new file backed up
my $bkp = Win32::Backup::Robocopy->new(
	name => 'test',
	source	 => $tsrc,
	dst => $tdst,	
);
my ($stdout, $stderr, $exit, $exitstr) = $bkp->run();
ok ( $exit == 1, "new file $file1 correctly backed up" );

# check $exit code: now has to be 0 as for no new file 
($stdout, $stderr, $exit, $exitstr) = $bkp->run( emptysufolders => 1 );
ok ( $exit == 0, "no new file present" );

# add some line to file
# check $exit code: now has to be 1 as for modified file
open $tfh1, '>>', $file1 or BAIL_OUT ("unable to append to $file1 in $tsrc!");
print $tfh1 "Venere, e fea quelle isole feconde\n",
			"  col suo primo sorriso, onde non tacque\n",
			"  le tue limpide nubi e le tue fronde\n",
			"  l'inclito verso di colui che l'acque\n";			
close $tfh1 or BAIL_OUT ("impossible to close $file1");
($stdout, $stderr, $exit, $exitstr) = $bkp->run( emptysufolders => 1 );
ok ( $exit == 1, "updated file $file1 correctly backed up" );

# try to backuk *.doc
($stdout, $stderr, $exit, $exitstr) = $bkp->run( files => '*.doc' );
ok ( $exit == 0, "no *.doc files to backed up" );

# check archive attribute was removed from the file
my $attr;
my $getattrexit = GetAttributes( $file1, $attr );
BAIL_OUT( "impossible to retrieve attributes of $file1" ) unless $getattrexit;
my $archiveset = $attr & ARCHIVE;
cmp_ok($archiveset, '==', 0, "ARCHIVE bit not present in $file1");

# modify another time the file and do an HISTORY backup
open $tfh1, '>>', $file1 or BAIL_OUT ("unable to append to $file1 in $tsrc!");
print $tfh1 "Cantò fatali, ed il diverso esiglio\n",
			"  per cui bello di fama e di sventura\n",
			"  baciò la sua petrosa Itaca Ulisse\n";
close $tfh1 or BAIL_OUT ("impossible to close $file1");
$bkp = Win32::Backup::Robocopy->new(
	name => 'test2',
	source	 => $tsrc,
	dst => $tdst,
	history => 1
);
my $createdfolder;
($stdout, $stderr, $exit, $exitstr,$createdfolder) = $bkp->run();
# check $exit code: now has to be 1 as for modified file
ok ( $exit == 1, "updated file $filename correctly backed up using history = 1" );

# check run with HISTORY returned the created folder
ok (defined $createdfolder, "history backup returned created folder [$createdfolder]");
# just to be sure another folder is created while history => 1
sleep 2;

# a final append to the file
open $tfh1, '>>', $file1 or BAIL_OUT ("unable to append to $file1 in $tsrc!");
print $tfh1 $_ for  "\nTu non altro che il canto avrai del figlio,\n",
					"  o materna mia terra; a noi prescrisse\n",
					"  il fato illacrimata sepoltura.\n";
close $tfh1 or BAIL_OUT ("impossible to close $file1");
# now we pass extraparam '/A+:R' meaning to set READONLY attribute on destination file
($stdout, $stderr, $exit, $exitstr) = $bkp->run( extraparam => '/A+:R' );
# check $exit code: now has to be 1 as for modified file
ok ( $exit == 1, "updated file $filename correctly backed up in a new folder while history = 1" );

# get the position of last HISTORY backup
my $completedest = File::Spec->catdir($bkp->{dst},$bkp->{name});
opendir my $lastdir, 
			$completedest,
			or BAIL_OUT ("Unable to read directory [$completedest]!");
my @ordered_dirs = sort grep {!/^\./} readdir($lastdir);
my $lastfilepath = File::Spec->catfile( $completedest, $ordered_dirs[-1], $filename);

# check the READONLY attributes was set in destination because of extraparam => '/A+:R'
my $lastattr;
my $lastgetattrexit = GetAttributes( $lastfilepath, $lastattr );
BAIL_OUT( "impossible to retrieve attributes of $lastfilepath".__LINE__ ) unless $lastgetattrexit;
my $lastreadonlyset = $lastattr & READONLY;
cmp_ok( $lastreadonlyset, '==', 1, "READONLY bit is present in $lastfilepath");

# check if last file is complete..
open my $lastfile, '<', $lastfilepath or 
					BAIL_OUT ("unable to open file to check it ($filename in $bkp->{dst} $ordered_dirs[-1])!");
my $last_line;
while(<$lastfile>){ $last_line = $_}
close $lastfile or BAIL_OUT("unable to close file!");
ok( $last_line eq "  il fato illacrimata sepoltura.\n","file $filename has the expected content in folder $ordered_dirs[-1]");

# remove the backup scenario
note("removing bakup scenario in $tbasedir");
remove_tree($tbasedir);
