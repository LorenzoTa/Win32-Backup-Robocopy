#!perl
use 5.010;
use strict;
use warnings;
use Data::Dumper;
use Test::More;
use Test::Exception;
use Capture::Tiny qw(capture);
use Win32::File qw(:DEFAULT GetAttributes SetAttributes);
use Win32::Backup::Robocopy;

use lib '.';
use t::bkpscenario;

plan tests => 12;

# run croaks if destination drive does not exists
my $nobkp = Win32::Backup::Robocopy->new( 
	name => 'impossible',
	src	 => '.',
	dst => File::Spec->catdir ( Win32::GetNextAvailDrive(),'' )
);
my ($out, $err, @res) = capture {
		dies_ok { $nobkp->run } 'run is expected to die with no existing destination drive';
};


# run croaks if invalid name was given for destination
$nobkp = Win32::Backup::Robocopy->new( 
	name => 'impos??????sible',
	verbose => 1,
	src	 => 'x:/',
	dst => '.', 
);
($out, $err, @res) = capture {
		dies_ok { $nobkp->run } 'run is expected to die with invalid folder name';
};


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
);
my ($stdout, $stderr, $exit, $exitstr) = $bkp->run();
ok ( $exit == 1, "new file $file1 correctly backed up" );

# check $exit code: now has to be 0 as for no new file 
($stdout, $stderr, $exit, $exitstr) = $bkp->run( emptysufolders => 1 );
if( not ok ( $exit == 0, "no new file present" ) ) {
	diag "basedir : $tbasedir\n",
		 "tempsrc : $tsrc\n",
		 "tempdst : $tdst\n",
		 "file    : $file1\n";
	diag "Dumping returned values from 'run'..\n";
	diag "stdout : $stdout\n";
	diag "stdrerr: $stderr\n";
	diag "exit   : $exit\n";
	diag "string : $exitstr\n";	
}

# add some line to file
# check $exit code: now has to be 1 as for modified file
$tfh1 = bkpscenario::open_file($tsrc,$file1);
bkpscenario::update_file($tfh1,1);
($stdout, $stderr, $exit, $exitstr) = $bkp->run( emptysufolders => 1 );
ok ( $exit == 1, "updated file $file1 correctly backed up" );

# C:\WINDOWS\system32>wmic datafile where name='c:\\windows\\system32\\robocopy.exe' get version
# Version
# 10.0.17134.1

# wikipedia 
# 1.71	4.0.1.71	1997	Windows NT Resource Kit	
# 1.95	4.0.1.95	1999	Windows 2000 Resource Kit	
# 1.96	4.0.1.96	1999	Windows 2000 Resource Kit	© 1995-1997
# XP010	5.1.1.1010	2003	Windows 2003 Resource Kit	
# XP026	5.1.2600.26	2005	Downloaded with Robocopy GUI v.3.1.2; /DCOPY:T option introduced	
# XP027	5.1.10.1027	2008	Bundled with Windows Vista, Server 2008, Windows 7, Server 2008r2	© 1995-2004
# 6.1	6.1.7601	2009	KB2639043	© 2009
# 6.2	6.2.9200	2012	Bundled with Windows 8	© 2012
# 6.3	6.3.9600	2013	Bundled with Windows 8.1	© 2013
# 10.0	10.0.10240.16384	2015	Bundled with Windows 10	© 2015
# 10.0.16	10.0.16299.15	2017	Bundled with Windows 10 1709	© 2017
# 10.0.17	10.0.17763.1	2018	Bundled with Windows 10 1809	© 2018


# try to backuk *.doc
($stdout, $stderr, $exit, $exitstr) = $bkp->run( files => '*.doc' );
#ok ( $exit == 0, "no *.doc files to backed up" );
if( not ok ( $exit == 55, "no *.doc files to backed up" ) ) {
	diag "basedir : $tbasedir\n",
		 "tempsrc : $tsrc\n",
		 "tempdst : $tdst\n",
		 "file    : $file1\n";
	diag "Dumping returned values from 'run'..\n";
	diag "stdout : $stdout\n";
	diag "stdrerr: $stderr\n";
	diag "exit   : $exit\n";
	diag "string : $exitstr\n";	
}

# check archive attribute was removed from the file
my $attr;
my $getattrexit = GetAttributes( File::Spec->catfile($tsrc, $file1), $attr );
BAIL_OUT( "impossible to retrieve attributes of $file1" ) unless $getattrexit;
my $archiveset = $attr & ARCHIVE;
cmp_ok($archiveset, '==', 0, "ARCHIVE bit not present in $file1");

# modify another time the file and do an HISTORY backup
$tfh1 = bkpscenario::open_file($tsrc,$file1);
bkpscenario::update_file($tfh1,2);

$bkp = Win32::Backup::Robocopy->new(
	name => 'test2',
	source	 => $tsrc,
	dst => $tdst,
	history => 1
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

# check the READONLY attributes was set in destination because of extraparam => '/A+:R'
my $lastattr;
my $lastgetattrexit = GetAttributes( $lastfilepath, $lastattr );
BAIL_OUT( "impossible to retrieve attributes of $lastfilepath".__LINE__ ) unless $lastgetattrexit;
my $lastreadonlyset = $lastattr & READONLY;
cmp_ok( $lastreadonlyset, '==', 1, "READONLY bit is present in dir $ordered_dirs[-1] file $file1");

# check if last file is complete..
open my $lastfile, '<', $lastfilepath or 
					BAIL_OUT ("unable to open file to check it ($file1 in $bkp->{dst} $ordered_dirs[-1])!");
my $last_line;
while(<$lastfile>){ $last_line = $_}
close $lastfile or BAIL_OUT("unable to close file!");
ok( $last_line eq "  il fato illacrimata sepoltura.\n","file $file1 has the expected content in folder $ordered_dirs[-1]");

# remove the backup scenario
bkpscenario::clean_all($tbasedir);
note("removed backup scenario in $tbasedir");