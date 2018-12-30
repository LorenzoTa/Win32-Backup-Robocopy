package Win32::Backup::Robocopy;

use 5.006;
use strict;
use warnings;
use Carp;
use File::Spec;
use File::Path qw(make_path);
use JSON::PP; # only this support sort_by(custom_func)
use Capture::Tiny qw(capture);
use DateTime::Tiny;
use Algorithm::Cron;
our $VERSION = 5;

# perl -I ./lib ./t/01-new.t & perl -I ./lib ./t/02-run.t &  perl -I ./lib ./t/03-job.t & perl -I ./lib ./t/04-runjobs.t & perl -I ./lib  ./t/05-writeconf.t
# AKA
# perl -e "system qq( $^X -I ./lib $_) for glob './t/[0-9]*.t'"
# AKA
# prove -I ./lib -v
# aka
# prove -l -v
#

# perl -I ./lib -MWin32::Backup::Robocopy -e "$bkp=Win32::Backup::Robocopy->new(name=>'test',src=>'.',dst=>'H:/test',waitdrive=>1); $bkp->run()"

# perl -nlE "BEGIN{@ARGV=glob shift}last if /__DATA__/;$c++ unless /^$|^\s*#/}{say $c" "./lib/Win32/Backup/Robocopy.pm"
# 321

# perl -nlE "BEGIN{@ARGV=glob shift}last if /__DATA__/;$c++ unless /^$|^\s*#/}{say $c" "./t/*.t"
# 376

# perl -I ./lib -MWin32::Backup::Robocopy -MData::Dump -e "$bkp=Win32::Backup::Robocopy->new(conf=>'bkpconfig.json'); $bkp->job(src=>'.',dst=>'x:/dest',name=>'first',cron=>'* 4 * * *'); $bkp->runjobs"

# perl -MModule::CPANTS::Analyse -MData::Dump -e "$an = Module::CPANTS::Analyse->new({dist=>$ARGV[0]}); $an->run; dd $an->d"

# cpants_lint.pl Foo-Bar-1.23.tar.gz

sub new {
	my $class = shift;
	my %arg = _default_new_params( @_ );
	# conf  config configuration aliases
	$arg{conf}//= $arg{config} // $arg{configuration};	
	# JOB mode: it just check for a configuration
	# parameter passed in and returns.
	# the $bkp object will be a mere container of jobs
	if ( $arg{conf} ){
			$arg{conf} = File::Spec->file_name_is_absolute( $arg{conf} ) ?
				$arg{conf} 									:
				File::Spec->rel2abs( $arg{conf} ) ;
			my $jobs = _load_conf( $arg{conf} );
			return bless {
				conf 		=> $arg{conf} ,
				jobs 		=> $jobs // [],
				verbose 	=> $arg{verbose},
				debug		=> $arg {debug},
				#writelog	=> $arg {writelog},
			}, $class;	
	}
	# RUN mode: the $bkp object will contains a serie
	# of defaults used by $bkp->run invocations
	%arg = _verify_args(%arg);
	return bless {
				name 		=> $arg{name},
				src			=> $arg{src},
				dst 		=> $arg{dst},
				history 	=> $arg{history} // 0,
				verbose 	=> $arg{verbose} // 0,
				debug		=> $arg{debug} // 0,
				waitdrive	=> $arg{waitdrive} // 0,
				#writelog	=> $arg {writelog} // 1,
	}, $class;
}
sub run	{
	my $self = shift;
	my %opt = _default_run_params(@_);
	# leave if we are running under JOB mode
	if ( $self->{jobs} and ref $self->{jobs} eq 'ARRAY' ){
		croak "No direct run invocation permitted while running in JOB mode!\n".
				"Perahps you intended to call runjobs?\n".
				"See the docs of ".__PACKAGE__." about different modes of instantiation\n";
		return undef;
	}
	# we are in RUN mode: continue..
	my $src = $self->{src};
	my $dst = File::Spec->file_name_is_absolute( $self->{dst} ) ?
				$self->{dst}									:
				File::Spec->rel2abs( $self->{dst} ) ;
	$dst = File::Spec->catdir( $dst, $self->{name} );
	# modify destination if history = 1
	my $date_folder;
	if ( $self->{history} ){
		$date_folder = DateTime::Tiny->now()=~s/:/-/gr;
		$dst =  File::Spec->catdir( $dst, $date_folder );		
	}
	# check the directories structure
	make_path( $dst, { 
						verbose => $self->{verbose},
						error => \my $filepatherror
	} );
	# Note that if no errors are encountered, $err will reference an empty array. 
	# This means that $err will always end up TRUE; so you need to test @$err to 
	# determine if errors occurred. (File::Path doc(s|et))
	# croak if errors, but check them twice:
	if (@$filepatherror){
		# dump first error received by File::Path
		carp "Folder creation errors: ".( join ' ', each %{$$filepatherror[0]} );
		# check if the, possibly remote, drive is present
		my @dirs = File::Spec->splitdir( $dst );
		unless ( -d $dirs[0] ){
			if ( $self->{waitdrive} ){
				$self->_waitdrive( $dirs[0] );
				return;
			}
			else { croak ("destination drive $dirs[0] is not accessible!") }
		}
		croak "Error in directory creation!"
	}
	# extra parameters to pass to robocopy 
	my @extra =  ref $opt{extraparam} eq 'ARRAY' 	?
					@{ $opt{extraparam} }			:
					split /\s+/, $opt{extraparam} // ''	;	
	my @cmdargs = grep { defined $_ } 
						# parameters managed by new
						$src, $dst,
						# parameters managed by run
						$opt{files},
						( $opt{subfolders} ? '/S' : undef ),
						( $opt{emptysubfolders} ? '/E' : undef ),
						( $opt{archive} ? '/A' : undef ),
						( $opt{archiveremove} ? '/M' : undef ),
						( $opt{noprogress} ? '/NP' : undef ),
						# extra parameters for robocopy
						@extra
						;
	my ($stdout, $stderr, $exit) = capture {
	  system( 'ROBOCOPY', @cmdargs );
	};
	# !!
	$exit = $exit>>8;
	my %exit_code = (
		0   =>  'No errors occurred, and no copying was done.'.
				'The source and destination directory trees are completely synchronized.',
		1   =>  'One or more files were copied successfully (that is, new files have arrived).',
		2   =>  'Some Extra files or directories were detected. No files were copied'.
				'Examine the output log for details.',
		4   =>  'Some Mismatched files or directories were detected.'.
				'Examine the output log. Housekeeping might be required.',
		8   =>  'Some files or directories could not be copied'.
				'(copy errors occurred and the retry limit was exceeded).'.
				'Check these errors further.',
		16  =>  'Serious error. Robocopy did not copy any files.'.
				'Either a usage error or an error due to insufficient access privileges'.
				'on the source or destination directories.'
	);
	my $exitstr = '';
	foreach my $code(sort {$a<=>$b} keys %exit_code){
		if ( $exit == 0){
			$exitstr .= $exit_code{0};
			last;
		}
		$exitstr .= $exit_code{$code} if ($exit & $code);
	}
	return $stdout, $stderr, $exit, $exitstr, $date_folder;
}

sub job {
	my $self = shift;
	# check if we are running under the correct JOB mode
	unless ( $self->{ jobs } and ref $self->{ jobs } eq 'ARRAY'){
		croak "No job invocation permitted while running in RUN mode!\n".
				"See the docs of ".__PACKAGE__." about different modes of instantiation\n";
		return undef;
	}
	# use deafults as for run method if not specified otherwise
	my %opt = _verify_args(@_);
	%opt = _default_new_params( %opt );	
	%opt = _default_run_params( %opt );
	# intialize first_time_run to 0
	$opt{ first_time_run } //= 0;
	# delete entries that must only be set internally
	delete $opt{ next_time };
	delete $opt{ next_time_descr };
	# check the cron option to be present
	croak "job method needs a crontab like string!" unless $opt{ cron };
	# get the cron onject
	my $cron = _get_cron( $opt{ cron } );		
	my $jobconf =
	# a job configuration is an hash of parameters..
		{
			# ..made of backup object parameters..
			( map{ $_ => $self->{$_} }qw(name src dst history) ),
			# ..and other parameters passed in via @_
			# and checked for defaults as we do for run method..
			%opt
		}      
	;
	# ..and the cron scheduling
	# depending if first_time_run is set..
	if ( $$jobconf{ first_time_run } ){
					$$jobconf{ next_time } = 0;
					$$jobconf{ first_time_run } = 0;
					$$jobconf{ next_time_descr } = '--AS SOON AS POSSIBLE--';
	}
	# or not
	else{ 
			$$jobconf{ next_time } = $cron->next_time(time);
			$$jobconf{ next_time_descr } = scalar localtime($cron->next_time(time));
	
	}	
	# JSON for the job 
	my $json = JSON::PP->new->utf8->pretty->canonical;
	$json->canonical(1);
	$json->sort_by( \&_ordered_json );
	push @{ $self->{jobs} }, $jobconf;
	# clean the main object of other (now unwanted) properties
	$self->_write_conf;
	map{ delete $self->{$_} }qw( name src dst history debug verbose );
}

sub runjobs{
	my $self = shift;
	# check if we are running under the correct JOB mode
	unless ( $self->{ jobs } and ref $self->{ jobs } eq 'ARRAY'){
		croak "No runjob invocation permitted with empty queue nor while running in RUN mode!\n".
				"See the docs of ".__PACKAGE__." about different modes of instantiation\n";
		return undef;
	}
	# accept a range instead of all jobs
	my $range = ( @_ ? (join ',',@_) : undef) // join '..',0,$#{ $self->{ jobs }};
	my @range = _validrange( $range );
	foreach my $job( @{ $self->{ jobs } }[@range] ){
		if ( $job->{ verbose } ){
			print "considering job [$job->{ name }]\n";
		}
		if ( time > $job->{ next_time } ){
			print "executing job [$job->{ name }]\n";
			# create a bkp object using values from the job
			# no need to use new because it's check will append
			# 'name' to destination a second time
			# and all parameters are already validated
			my $bkp = bless{
				name 		=> $job->{name},
				src			=> $job->{src},
				dst 		=> $job->{dst},
				history 	=> $job->{history} // 0,
				verbose 	=> $job->{verbose} // 0,
				debug		=> $job->{debug} // 0,
				#writelog	=> $job->{writelog} // 1,
			},ref $self;		
			
			$bkp->run( 
				archive => $job->{archive},
                archiveremove => $job->{archiveremove},
				subfolders => $job->{subfolders},
				emptysubfolders => $job->{emptysubfolders},
				files => $job->{files},
				noprogress => $job->{noprogress},				
			);
			# updating next_time* in the job
			my $cron = _get_cron( $job->{ cron } );
			$job->{ next_time } = $cron->next_time(time);
			$job->{ next_time_descr } = scalar localtime($cron->next_time(time));
			# write configuration
			$self->_write_conf;
		}
		# job not to be executed
		else {
			print "is not time to execute [$job->{ name }] (next time will be $job->{ next_time_descr })\n";
		}
	}	
}
sub listjobs{
	my $self = shift;
	my %arg = @_;
	$arg{format} //= 'compact';
	$arg{fields} //= [qw( name src dst files history cron next_time next_time_descr
							first_time_run archive archiveremove subfolders emptysubfolders
							noprogress waitdrive verbose debug)];
							
	unless ( wantarray ){ return scalar @{$self->{jobs}} }
	my @res;
	my $count = 0;
	my $long = 1 if $arg{format} eq 'long';
	
	foreach my $job ( @{$self->{jobs}} ){
	
		push @res,  ( $long ? "JOB $count:\n" : '').
					join ' ',map{ 
									($long ? "\t" : '').
									"$_ = $job->{$_}".
									($long ? "\n" : '')
					
					} @{$arg{fields}};
	$count++;	
	}
	return @res;
}
##################################################################
# not public subs
##################################################################
sub _validrange {
	my $range = shift;
	$range =~ s/\s//g;
	my @range;
	# allowed only . , \d \s
	croak 'invalid range ['.$range.'] (allowed only [\s.,\d])!' if $range =~ /[^\s,.\d]/;
	# not allowed a lone .
	croak 'invalid range ['.$range.'] (single .)!' if $range =~ /(?<!\.)\.(?!\.)/;
	# not allowed more than 2 .
	croak 'invalid range ['.$range.'] (more than 2 .)!' if $range =~ /\.{3}/;
	# $1 > $2 like in 25..7
	 if ($range =~ /[^.]\.\.[^.]/){
		foreach my $match ( $range=~/(\d+\.\.\d+)/g ){
			$match=~/(\d+)\.\.(\d+)/;
			croak "$1 > $2 in range [$range]" if $1 > $2;
		}
	}
	@range = eval ($range);
	my %single = map{ $_ => 1} @range;
	@range = sort{ $a <=> $b } keys %single;
	#print "RANGE:@range\n";
	return @range;
}
sub _waitdrive{
	my $self = shift;
	my $drive = shift;
	print 	"\nBackup of:     $self->{src}\n".
			"To:              $self->{dst}\n".
			"Waiting for drive $drive to be available..\n".
			"(press ENTER when $drive is connected or CTRL-C to terminate the program)\n";
	my $input = <STDIN>;
	$self->run();
}
sub _load_conf{ 
	my $file = shift;
	return [] unless -e -r -f $file;
	#print "loading configuration in $file\n";
	# READ the configuration 
	my $json = JSON::PP->new->utf8->pretty->canonical;
	open my $fh, '<', $file or croak "unable to read $file";
	my $lines;
	{
		local $/ = '';
		$lines = <$fh>;
	}
	close $fh or croak "impossible to close $file";
	my $data;
	{ 
		local $@;
		eval { $data = $json->decode( $lines ) };
		croak "malformed json in $file!\nJSON error:\n[$@]\n" if $@;
	}
	croak "not an ARRAY ref retrieved from $file as conteainer for jobs! wrong configuration" 
			unless ref $data eq 'ARRAY';
	my @check = qw( name src dst files history cron next_time next_time_descr first_time_run archive
				archiveremove subfolders emptysubfolders noprogress verbose debug waitdrive);
	my $count = 1;
	foreach my $job ( @$data ){
		croak "not a HASH ref retrieved from $file for job $count! wrong configuration" 
			unless ref $job eq 'HASH';
		map { 
				croak "field [$_] not present in the job $count retrieved from $file" 
				unless exists $job->{ $_ } 
		} @check;
		carp "unexpected elements in job $count  retrieved from $file" if keys %$job > @check;
		$count++;
	}
	return $data;
}
sub _write_conf{
	my $self = shift;
	my $json = JSON::PP->new->utf8->pretty->canonical;
	$json->sort_by( \&_ordered_json );
	if ( $self->{ verbose } and -e $self->{ conf } ){
		carp "overwriting configuration file $self->{ conf }\n";
	}
	open my $fh, '>', $self->{ conf } or croak "unable to write configuration to [$self->{ conf }]";
	print $fh $json->encode( $self->{ jobs } );
	close $fh or croak "unable to close configuration file [$self->{ conf }]";	
}
sub _get_cron{
	my $crontab = shift;
	my $cron;
	# a safe scope for $@ 
	{  
		local $@;
		eval { 
				$cron = Algorithm::Cron->new(
												base => 'local',
												crontab => $crontab 
											)
		};
		if ( $@ ){
			croak "specify a valid cron entry as cron parameter!\n".
					"\tAlgorithm::Cron error is: $@" unless $cron;			
		}
	} 
	# end of safe scope for $@	
	return $cron;
}
sub _ordered_json{
	my %order = (
							# USED IN:
			name 	=> 0, 	# new
			src		=> 1, 	# new
			dst		=> 2, 	# new
			files	=> 3, 	# run
			history	=> 4, 	# new
			
			cron	=> 5, 		# job
			next_time=> 6,		# job RO
			next_time_descr=> 7,# job RO
			first_time_run=>7.5,# job
			
			archive=> 8,		 # run
			archiveremove=> 9,	 # run
			subfolders=> 10,	 # run
			emptysubfolders=> 11,# run
			noprogress=> 12,	 # run		
			
			waitdrive => 12.5,	# new
			verbose	=> 13, 		# new
			debug	=>	15, 	# new
	);
	($order{$JSON::PP::a} // 99) <=> ($order{$JSON::PP::b} // 99)
}
sub _default_new_params{
	my %opt = @_;
	$opt{history} //= 0;
	$opt{verbose} //= 0;
	$opt{debug} //= 0;
	$opt{waitdrive} //= 0;
	#$opt{writelog} //= 1;
	return %opt;
}
sub _default_run_params{
	my %opt = @_;
	# process received options
	# file options
	$opt{files} //= '*.*',	
	# source options
	# /S : Copy Subfolders.
	$opt{subfolders} //= 0;
	# /E : Copy Subfolders, including Empty Subfolders.
	$opt{emptysubfolders} //= 1;
	# /A : Copy only files with the Archive attribute set.
	$opt{archive} //= 0;
	# /M : like /A, but remove Archive attribute from source files.
	$opt{archiveremove} //= 1;	
	# logging options
    # /NP : No Progress - don’t display % copied.
	$opt{noprogress} //= 1;
	return %opt;
}
sub _verify_args{
	my %arg = @_;
	croak "backup need a name!" unless $arg{name};
	$arg{src} //= $arg{source};
	croak "backup need a source!" unless $arg{src};
	$arg{dst} //= $arg{destination} // '.';
	############$arg{dst} = File::Spec->catdir( $arg{dst}, $arg{name} );
	map { $_ =  File::Spec->file_name_is_absolute( $_ ) ?
				$_ 										:
				File::Spec->rel2abs( $_ ) ;
	} $arg{src}, $arg{dst};
	carp "backup source [$arg{src}] does not exists!".
			"(this is only a warning)" unless -d $arg{src};
	return %arg;	
}
1;

__DATA__

=head1 NAME

Win32::Backup::Robocopy - a simple backup solution using robocopy


=cut

=head1 SYNOPSIS

    use Win32::Backup::Robocopy;

    # RUN mode 
    my $bkp = Win32::Backup::Robocopy->new(
            name 	=> 'my_perl_archive',        
            source	=> 'x:\scripts',             
            history	=> 1                         
    );
    my( $stdout, $stderr, $exit, $exitstr, $createdfolder ) = $bkp->run();

	
    # JOB mode 
    my $bkp = Win32::Backup::Robocopy->new( configuration => './my_conf.json' );
    $bkp->job( 	
                name=>'my_backup_name',          
                src=>'./a_folder',               
                history=>1,                      
				
                cron=>'0 0 25 12 *',             
                first_time_run=>1                
    );
    $bkp->runjobs;              




=head1 DESCRIPTION

This module is a wrapper around C<robocopy.exe> and try to make it's behaviour as simple as possible
using a serie of sane defaults while letting you the possibility to leverage the C<robocopy.exe>
invocation in your own way.

The module offers two modes of being used: the RUN mode and the JOB mode. In the RUN mode a backup object created via C<new> is a_folder
single backup intended to be run using the C<run> method. In the JOB mode the object is a container of scheduled jobs filled reading
a JSON configuration file and/or using the C<job> method. C<runjobs> is then used to cycle the job list and see if some job has to be run.

In the RUN mode, if not C<history> is specified as true, the  backup object (using the C<run> method) will copy all files to one folder, named
as the name of the backup (the mandatory C<name> parameter used while creating the object). All successive
invocation of the backup will write into the same destination folder.

    # RUN mode with all files to the same folder
    use Win32::Backup::Robocopy;

    my $bkp = Win32::Backup::Robocopy->new(
            name 	=> 'my_perl_archive',       # mandatory
            source	=> 'x:\scripts'             # mandatory
    );
	
    my( $stdout, $stderr, $exit, $exitstr ) = $bkp->run();
	
If you instead specify the C<history> parameter as true during construction, then inside the main 
destination folder ( always named using the C<name> ) there will be one folder for each run of the backup
named using a timestamp like C<2022-04-12T09-02-36> 

    # RUN mode with history folders in destination
    my $bkp = Win32::Backup::Robocopy->new(
            name 	=> 'my_perl_archive',       # mandatory
            source	=> 'x:\scripts',            # mandatory
            history	=> 1                        # optional
    );
	
    my( $stdout, $stderr, $exit, $exitstr, $createdfolder ) = $bkp->run();

The second mode is the JOB one. In this mode yuo must only specify a C<config> parameter during the object instantiation. You can
add different jobs to the queue or load them from a configuration file. Configuration file is read and written in JSON.
Then you just call C<runjobs> method to process them all.
The JOB mode add the possibility of scheduling jobs using C<crontab> like strings (using L<Algorithm::Cron> under the hoods). 


    # JOB mode - loading jobs from configuration file

    my $bkp = Win32::Backup::Robocopy->new( configuration => './my_conf.json' ); # mandatory configuration file

    $bkp->runjobs;
	
You can add jobs to the queue using the C<job> method. This method will accepts all parameters and assumes all defautls of
the C<new> method in the RUN mode and of the C<run> method of the RUN mode. The C<job> method add
a crontab like entry to have the job run only when needed. You can also specify C<first_time_run> to 1 to have the job run
a first time without checking the cron scheduling, ie at the firt invocation of C<runjobs>

    # JOB mode - adding  jobs 
	
    my $bkp = Win32::Backup::Robocopy->new( configuration => './my_conf.json' ); # mandatory configuration file
    

    $bkp->job( 	
                name=>'my_backup_name',         # mandatory as per new
                src=>'./a_folder',              # mandatory as per new
                history=>1,                     # optional as per new
				
                cron=>'0 0 25 12 *',            # job specific, mandatory
                first_time_run=>1               # job specific, optional
    );

    # add more jobs..
	
    $bkp->runjobs;              


=head1 METHODS (RUN mode)

=head2 new

As already stated C<new> only needs two mandatory parameters: C<name> ( the name of the backup governing
the destination folder name too) and C<source> ( you can use also the abbreviated C<src> form ) that
specify what you intend to backup. The C<new> method will emit a warning if the source for the backup
does not exists but do not exit the program: this can be useful to spot a typo leaving to you if the is
the right thing (maybe you want to backup a remote folder not available at the moment).

If you do not specify a C<destination> ( or the abbreviated form C<dst> ) you'll have backup folders created
inside the current directory, ie the module assumes C<destination> to be C<'.'> unless specified.
During the object construction C<destination> will be crafted using the provided path and the C<name>
you used for the backup.

If your current running program is in the C<c:/scripts> directory the following invocation

    my $bkp = Win32::Backup::Robocopy->new(
            name 	=> 'my_perl_archive',       
            source	=> 'x:\perl_stuff',            
    );

will produces a C<destination> equal to C<c:/scripts/my_perl_archive> and here willl be backed up your files.
By other hand:

    my $bkp = Win32::Backup::Robocopy->new(
            name 	=> 'my_perl_archive',       
            source	=> 'x:\scripts',            
            destination => 'Z:\backups'
    );

will produces a C<destination> equal to C<Z:/backups/my_perl_archive>


All paths and filenames passed in during costruction will be checked to be absolute and if needed made absolute
using L<File::Spec> so you can be quite sure the rigth thing will be done with relative paths.

The C<new> method does not do any check against folders for existence, it merely prepare folder names to be used by C<run>

The module provide a mechanism to spot unavailable destination drive and ask the user to connect it. If you 
specify C<waitdrive =E<gt> 1> during the object construction then the program will not die when the drive specified
for the destination folder is not present. Instead it opens a prompt asking the user to connect the appropriate drive
to continue. The deafult value of C<waitdrive> is 0 ie. the program will die for the drive to be unavailable and
creation of the destination folder impossible.

Wait for the drive is useful in case of backups with destination, let's say, an USB drive:

    my $bkp=Win32::Backup::Robocopy->new( 
                                          name => 'test', 
                                          src  => '.',
                                          dst  => 'H:/test',     # drive is unplagged
                                          waitdrive => 1         # force asking the user
    ); 
	
    $bkp->run();
	
    # output:
	
    Backup of:     D:\my_current\dir
    To:            H:\test\test
    Waiting for drive H: to be available..
    (press ENTER when H: is connected or CTRL-C to terminate the program)
	
    # I press enter before plugging the drive..
	
    Backup of:     D:\my_current\dir
    To:            H:\test\test
    Waiting for drive H: to be available..
    (press ENTER when H: is connected or CTRL-C to terminate the program)

    # I plug the external hard disk that receive the H: letter, then  I press ENTER
    # the backup run OK

With C<waitdrive> set to 0 instead the above program dies complaining about directory creation errors and C<destination drive H: is not accessible!>	


Overview of parameters accepted by C<new> and their defaults:


=over 

=item 

C<name> mandatory. Will be used to create the destination folder appended to C<dest>

=item 

C<source> or C<src> mandatory. 


=item 

C<destination> or C<dst> defaults to C<'./'> 


=item 

C<history> defaults to 0 meaning all invocation of the backup will write to the same folder or folder with timestamp if true

=item 

C<waitdrive> defaults to 0 stopping the program if destination drive does not exists, asking the user if true

=item 

C<verbose> defaults to 0 governs the output of the program

=item 

C<debug> defaults to 0 dumping objects and configuration if true

=back




=head2 run

This method will effectively run the backup. It checks needed folder for existence and try to create them using L<File::Path>
and will croak if error are encountered.
If C<run> is invoked without any optional parameter C<run> will assumes some default options to pass to the C<robocopy> 
system call:

=over 

=item 

C<files> defaults to C<*.*>  robocopy will assumes all file unless specified: the module passes it explicitly (see below)

=item 

C<archive> defaults to 0 and will set the C</A> ( copy only files with the archive attribute set ) robocopy switch

=item 

C<archiveremove> defaults to 1 and will set the C</M> ( like C</A>, but remove archive attribute from source files ) robocopy switch

=item 

C<subfolders> defaults to 0 and will set the C</S> ( copy subfolders ) robocopy switch

=item 

C<emptysubfolders> defaults to 1 and will set the C</E> ( copy subfolders, including empty subfolders ) robocopy switch

=item 

C<noprogress> defaults to 1 and will set the C</NP> ( no progress - do not display % copied ) robocopy switch

=item 

C<extraparam> defaults to undef and can be used to pass any valid option to robocopy (see below)

=back

So if you dont want empty subfolders to be backed up you can run:

	$bkp->run( emptysufolders => 0 )
	
Pay attention modifying C<archive> and C<archiveremove> parameters: infact this is the basic machanism of the backup: on MSWin32 OSs
whenever a file is created or modified the archive bit is set. This module with it's defualts values of C<archive> and C<archiveremove>
will backup only new or modified files and will unset the archive bit in the original file.

The C<run> method effectively executes the C<robocopy.exe> system call using L<Capture::Tiny> C<capture> method.
The C<run> method returns four elements: 1) the output emitted by the system call, 2) the error stream eventually produced,
3) the exit code of the call ( first three elements provided by L<Capture::Tiny> ) and 4) the text relative to the exit code. A fifth 
returned value will be present if the backup has C<history =E<gt> 1> and it's value will be the name of the folder with timestamp just created.

	my( $stdout, $stderr, $exit, $exitstr ) = $bkp->run();
	
	# or in case of history backup:
	# my( $stdout, $stderr, $exit, $exitstr, $createdfolder ) = $bkp->run();
	
	# an exit code of 7 or less is a success
	if ( $exit < 8 ){
		print "backup successful: $exitstr\n";
	}
	else{ print "some problem occurred\n",
                "OUTPUT: $stdout\n",
                "ERROR: $stderr\n",
                "EXIT: $exit\n",
                "EXITSTRING: $existr\n";				
	}
	
Read about C<robocopy.exe> exit codes L<here|https://ss64.com/nt/robocopy-exit.html>

C<robocopy.exe> accepts, after source and destination, a third parameter in the form of a list of files or wildcard.
C<robocopy.exe> assumes this to be C<*.*> unless specified but the present module passes it always explicitly to let
you to modify it at your will. To backup just C<*.pl> files invoke C<run> as follow:

    $bkp->run( files => '*.pl');  

You can read more about Windows wildcards L<here|https://ss64.com/nt/syntax-wildcards.html>	

C<robocopy.exe> accepts a lot of parameters and the present module just plays around a handfull of them, but
you can pass any desired parameter using C<extraparam> so if you need to have all destination files to be readonly you 
can profit the C</A+:[RASHCNET]> robocopy option:

    $bkp->run( extraparam => '/A+:R');

C<extraparam> accepts both a string or an array reference.	

Read about all parameters accepted by C<robocopy.exe> L<here|https://ss64.com/nt/robocopy.html>

=cut


=head1 METHODS (JOB mode)

=head2 new

The only mandatory parameter needed by C<new> is C<conf> (or C<config> or C<configuration>) while in JOB mode. 
The value passed will be transformed into an absolute path and if the file exists and is readable and it contains
a valid JSON datastructure, the configuration is loaded and the job queue filled accordingly.

If, by other hand, the file does not exists,  C<new> does not complain, assuming the queue of jobs to be filled
soon using the C<job> method described below.


=head2 job

This method will push job in the queue. It accepts all parameters of the C<new> and the C<run> methods described in RUN mode above.
Infact a job, when run, will instantiate a new backup oject and will run via the C<run> method.

In addition it must be feed with a valid crontab like string via the C<cron> parameter with a value something 
like, for example, C<'15 14 1 * *'> to setup the schedule for this job to the first day of the month at 14:15

You can specify the optional parameter C<first_time_run =E<gt> 1> to have the job scheduled as soon as possible. Then, after
the first time the job will run following the schedule given by the C<cron> parameter.

Everytime a job is added the configuration file will be updated accordingly.


=head2 runjobs

This is the method to cycle the job queue to see if something has to be run. If so the job is run and the configuration file 
is immediately updated with the correct time for the next execution.


=head2 listjobs

With C<listjobs> you can list all jobs currently present in the configuration. In scalar context it just returns the number of jobs
while il list context it returns the list of jobs.

In the list form you have the possibility to define the format used to represent the job with the C<format> parameter: if it is C<short>
(and is the default value) each job will be represented on his own line. If by other hand  C<format =E<gt> 'long'> a more fancy multiline
string will be crafted for each job.

You can also specify a list of fields you want to show instead to have them all present, passing an array reference as value of the
C<fields> parameter.

    # sclar context
    my $jobcount = $bkp->listjobs;
    print "there are $jobcont jobs configured";

    # list context: all fields returned in compact mode
    print "$_\n" for $bkp->listjobs;

    # output:
    name = job1 src = x:\path1 dst = F:\bkp\job1 files =  ...(all other fields and values following)
    name = job2 src = y:\path2 dst = F:\bkp\job2 files =  ...

    # list context: some field returned in compact mode
    print "$_\n" for $bkp->listjobs(fields => [qw(name src next_time_descr)]);

    # output:
    name = job1 src = x:\path1 next_time_descr = Tue Jan  1 00:05:00 2019
    name = job2 src = y:\path2 next_time_descr = Mon Apr  1 00:03:00 2019

    # list context, long format just some field
    print "$_\n" for $bkp->listjobs( format=>'long', fields => [qw(name src next_time_descr)]);

    # output:
    JOB 0:
            name = job1
            src = D:\ulisseDUE\Win32-Backup-Robocopy-job-mode
            next_time_descr = Tue Jan  1 00:05:00 2019

    JOB 1:
            name = job2
            src = D:\ulisseDUE\Win32-Backup-Robocopy-job-mode
            next_time_descr = Mon Apr  1 00:03:00 2019


=head1 CONFIGURATION FILE

The configuration file holds JSON data into an array each element of the array being a job, contained in a hash.
Writing to the configuration file done by the present module will maintain the job hash ordered using L<JSON::PP>

    my $bkp = Win32::Backup::Robocopy->new(conf=>'bkpconfig.json'); 
	
    $bkp->job( src => '.', dst => 'x:/dest', name => 'first', cron => '* 4 * * *' ); 
	
    $bkp->runjobs;
	
	
Will produce the following configuration:


  [
     {
      "name" : "first",
      "src" : "D:\\path\\stuff_to_backup",
      "dst" : "X:\\dest\\first",
      "files" : "*.*",
      "history" : 0,
      "cron" : "* 4 * * *",
      "next_time" : 1543546800,
      "next_time_descr" : "Fri Nov 30 04:00:00 2018",
      "first_time_run" : 0,
      "archive" : 0,
      "archiveremove" : 1,
      "subfolders" : 0,
      "emptysubfolders" : 1,
      "noprogress" : 1,
      "waitdrive" : 0,
      "verbose" : 0,
      "debug" : 0
     }
  ]

you can freely add and modify by hand the configuration file, paying attention to the C<next_time> and C<next_time_descr> entries
that are respectively seconds since epoch for the next scheduled run and the human readable form of the previous entry.
Note that C<next_time_descr> is just a label and does not affect the effective running time.

=head1 EXAMPLES


=head1 AUTHOR

LorenzoTa, C<< <lorenzo at cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-win32-backup-robocopy at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Win32-Backup-Robocopy>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

Main support site for this module is L<perlmonks.org|https://www.perlmonks.org>
You can find documentation for this module with the perldoc command.

    perldoc Win32::Backup::Robocopy


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Win32-Backup-Robocopy>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Win32-Backup-Robocopy>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Win32-Backup-Robocopy>

=item * Search CPAN

L<http://search.cpan.org/dist/Win32-Backup-Robocopy/>

=back


=head1 ACKNOWLEDGEMENTS

This software, as all my works, would be impossible without the continuous support and incitement of the L<perlmonks.org|https://www.perlmonks.org>
community

=head1 LICENSE AND COPYRIGHT

Copyright 2018 LorenzoTa.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut


