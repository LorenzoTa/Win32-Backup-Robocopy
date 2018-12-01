#!perl
use 5.006;
use strict;
use warnings;
use Test::More qw(no_plan);
use Test::Exception;
use Win32::Backup::Robocopy;
#perl -E "map{ say $_.(/[^.]+\.{1}[^.]+/ || /[^.]+\.{3}/ ?' NO':' OK')}@ARGV" 
#"1,3..5,8....9" "1...3" "1.2" "1,3,5..8,9.70" "1..3" "1..3,4..6,8...10"

foreach my $no ( 'x','3x','3-4', '1..3,4.4', '1..3,4...6','1.3','1...3'){
	dies_ok { Win32::Backup::Robocopy::_validrange($no) } "invalid range [$no]";
}