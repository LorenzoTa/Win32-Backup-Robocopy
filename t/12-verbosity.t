#!perl
use 5.006;
use strict;
use warnings;
use Test::More;
use Test::Exception;
use Win32::Backup::Robocopy;

use lib '.';
use t::bkpscenario;

#plan tests => 12;


#######################################################################
# a real minimal bkp scenario
#######################################################################
my ($tbasedir,$tsrc,$tdst) = bkpscenario::create_dirs();
BAIL_OUT( "unable to create temporary folders!" ) unless $tbasedir;
note("created backup scenario in $tbasedir");

my $file1 = 'Foscolo_A_Zacinto.txt';
my $tfh1 = bkpscenario::open_file($tsrc,$file1);
BAIL_OUT( "unable to create temporary file!" ) unless $tfh1;

bkpscenario::update_file($tfh1,0);			

# check $exit code: now has to be 1 as for new file backed up
my $bkp = Win32::Backup::Robocopy->new(
	name => 'test',
	source	 => $tsrc,
	dst => $tdst,
	verbose => 1,
);
my ($stdout, $stderr, $exit, $exitstr) = $bkp->run();
ok ( $exit == 1, "new file $file1 correctly backed up" );


# check $exit code: now has to be 0 as for no new file 
($stdout, $stderr, $exit, $exitstr) = $bkp->run( emptysufolders => 1 );
ok ( $exit == 0, "no new file present" );

# add some line to file
# check $exit code: now has to be 1 as for modified file
$tfh1 = bkpscenario::open_file($tsrc,$file1);
bkpscenario::update_file($tfh1,1);
($stdout, $stderr, $exit, $exitstr) = $bkp->run( emptysufolders => 1 );
ok ( $exit == 1, "updated file $file1 correctly backed up" );

# try to backup *.doc
($stdout, $stderr, $exit, $exitstr) = $bkp->run( files => '*.doc' );
ok ( $exit == 0, "no *.doc files to backed up" );


# modify another time the file and do an HISTORY backup
$tfh1 = bkpscenario::open_file($tsrc,$file1);
bkpscenario::update_file($tfh1,2);

$bkp = Win32::Backup::Robocopy->new(
	name => 'test2',
	source	 => $tsrc,
	dst => $tdst,
	history => 1,
	verbose => 2,
);
my $createdfolder;
($stdout, $stderr, $exit, $exitstr,$createdfolder) = $bkp->run();
# check $exit code: now has to be 1 as for modified file
ok ( $exit == 1, "updated file $file1 correctly backed up using history = 1" );

# check run with HISTORY returned the created folder
ok (defined $createdfolder, "history backup returned created folder [$createdfolder]");
# just to be sure another folder is created while history => 1
sleep 2;

# a final append to the file
$tfh1 = bkpscenario::open_file($tsrc,$file1);
bkpscenario::update_file($tfh1,3);

# now we pass extraparam '/A+:R' meaning to set READONLY attribute on destination file
($stdout, $stderr, $exit, $exitstr) = $bkp->run( extraparam => '/A+:R' );
# check $exit code: now has to be 1 as for modified file
ok ( $exit == 1, "updated file $file1 correctly backed up in a new folder while history = 1" );

# get the position of last HISTORY backup
my $completedest = File::Spec->catdir($bkp->{dst},$bkp->{name});
opendir my $lastdir, 
			$completedest,
			or BAIL_OUT ("Unable to read directory [$completedest]!");
my @ordered_dirs = sort grep {!/^\./} readdir($lastdir);
my $lastfilepath = File::Spec->catfile( $completedest, $ordered_dirs[-1], $file1);



# check if last file is complete..
open my $lastfile, '<', $lastfilepath or 
					BAIL_OUT ("unable to open file to check it ($file1 in $bkp->{dst} $ordered_dirs[-1])!");
my $last_line;
while(<$lastfile>){ $last_line = $_}
close $lastfile or BAIL_OUT("unable to close file!");
ok( $last_line eq "  il fato illacrimata sepoltura.\n","file $file1 has the expected content in folder $ordered_dirs[-1]");

# some restore
note("setting restore verbosity to 1");
$bkp->restore(from=> $completedest, to => $tbasedir, verbose => 1);
note("setting restore verbosity to 2");
$bkp->restore(from=> $completedest, to => $tbasedir, upto=> $ordered_dirs[-2], verbose => 2);
note("setting restore verbosity to 0");
$bkp->restore(from=> $completedest, to => $tbasedir, upto=> $ordered_dirs[-2], verbose => 0);


done_testing();
# remove the backup scenario
bkpscenario::clean_all($tbasedir);
note("removed backup scenario in $tbasedir");