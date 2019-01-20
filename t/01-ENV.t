#!perl
use 5.010;
use strict;
use warnings;
use Test::More;
use Test::Exception;

use Data::Dump;
# testing ENV
BEGIN
{
	my $try = 'c:\robocopy.exe';
	note("try using $try");
	$ENV{PERL_ROBOCOPY_EXE} = $try;
	dies_ok { require Win32::Backup::Robocopy } 
		'expected to die with not existent executable';

#delete $INC{'Win32/Backup/Robocopy.pm'};
print "--->$_ \n" for grep{/Robocopy/} keys %INC;			

}

BEGIN
{
	my $try = -e 'C:\Windows\System32\drivers\etc\HOSTS' ?
					'C:\Windows\System32\drivers\etc\HOSTS' :
					# systenative used if a 32bit perl. See
					# filesystem redirection oddities
					'C:\Windows\Sysnative\drivers\etc\HOSTS';
	note("try using $try");
	$ENV{PERL_ROBOCOPY_EXE} = $try;
	dies_ok { require Win32::Backup::Robocopy } 
		'expected to die with not executable file';
#delete $INC{'Win32/Backup/Robocopy.pm'};
print "--->$_\n" for grep{/Robocopy/} keys %INC;		
}

BEGIN{
	my $try = -e 'C:\Windows\System32\robocopy.exe' ? 
					'C:\Windows\System32\robocopy.exe' :
					'C:\Windows\Sysnative\robocopy.exe';
	note("try using $try");
	$ENV{PERL_ROBOCOPY_EXE} = $try;
#delete $INC{'Win32::Backup::Robocopy'};
	ok (require Win32::Backup::Robocopy, 'default executable path');
}

done_testing();