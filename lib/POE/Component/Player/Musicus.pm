package POE::Component::Player::Musicus;

use warnings;
use strict;

use POE;
use POE::Component::Child;
use Text::Balanced qw(extract_quotelike);
our @ISA = 'POE::Component::Child';

our $VERSION = '1.12';

sub new {
	my $class = shift;

	my %params = (
		# Options
		path	=> '/usr/lib/xmms/',
		output	=> 'libOSS.so',
		musicus	=> 'musicus',
		alias	=> 'main',

		# Events
		error		=> 'error',
		musicuserror	=> 'musicuserror',
		done		=> 'done',
		died		=> 'died',
		quit		=> 'quit',
		version		=> 'version',
		setvol		=> 'setvol',
		getvol		=> 'getvol',
		play		=> 'play',
		stop		=> 'stop',
		pause		=> 'pause',
		unpause		=> 'unpause',
		getpos		=> 'getpos',
		setpos		=> 'setpos',
		getlength	=> 'getlength',
		getinfocurr	=> 'getinfocurr',
		getinfo		=> 'getinfo',
		ready		=> 'ready',
		@_,
	);

	my @events = ();
	if($params{done}) { push @events, 'done', $params{done}; }
	if($params{died}) { push @events, 'died', $params{died}; }

	my $writemap;
	foreach (qw( quit version getvol stop pause unpause getpos getlength getinfocurr )) {
		$writemap->{$_} = $_;
	}

	# Define the stdout sub here so it doesn't look like a method that can be used by other modules
	my $stdout = sub {
		my ($self, $args) = @_;
		local $_ = $args->{out};

		if($self->{debug}) {
			print STDERR "PoCo::Player::Musicus got input: [$_]\n";
		}

		if (/^\@ OK getpos (.+?)\s*$/) {
			POE::Kernel->post($self->{alias}, $self->{getpos}, $1);
		} elsif (/^\@ OK quit\s*$/) {
			POE::Kernel->post($self->{alias}, $self->{quit});
		} elsif (/^\@ OK version (.+?)\s*$/) {
			POE::Kernel->post($self->{alias}, $self->{version}, $1);
		} elsif (/^\@ OK setvol\s*$/) {
			POE::Kernel->post($self->{alias}, $self->{setvol});
		} elsif (/^\@ OK getvol (.+?) (.+?)\s*$/) {
			POE::Kernel->post($self->{alias}, $self->{getvol}, $1, $2);
		} elsif (/^\@ OK play "(.+?)"\s*$/) {
			POE::Kernel->post($self->{alias}, $self->{play}, $1);
		} elsif (/^\@ OK stop\s*$/ ) {
			POE::Kernel->post($self->{alias}, $self->{stop});
		} elsif (/^\@ OK pause\s*$/) {
			POE::Kernel->post($self->{alias}, $self->{pause});
		} elsif (/^\@ OK unpause\s*$/) {
			POE::Kernel->post($self->{alias}, $self->{unpause});
		} elsif (/^\@ OK setpos (.+?)\s*$/) {
			POE::Kernel->post($self->{alias}, $self->{setpos}, $1);
		} elsif (/^\@ OK getlength (.+?)\s*$/) {
			POE::Kernel->post($self->{alias}, $self->{getlength}, $1);
		} elsif (/^# Entering interactive mode\s*$/) {
			POE::Kernel->post($self->{alias}, $self->{ready});
		} elsif (my ($command, $songinfo) = /^\@ OK (getinfocurr|getinfo) (.*)/) {
			my ($file, $songinfo) = (extract_quotelike($songinfo))[5,1];
			$file =~ s#\\"#"#g; # Musicus only escapes double quotes
			($songinfo) = (extract_quotelike($songinfo))[5];
			$songinfo =~ s#\\"#"#g; #  Musicus only escapes double quotes
			my ($length, $title) = $songinfo =~ /^(\d+)( .*)$/;
			my %info = (
				file	=> $file,
				length	=> $length,
			);
			
			if(my %tags = $title =~ / \x1e(\w)=([^\x1e]*?)(?= \x1e|\t)/g) {
				%info = (
					%info,
					artist	=> $tags{p},
					title	=> $tags{t},
					album	=> $tags{a},
					track	=> $tags{n},
					year	=> $tags{y},
					date	=> $tags{d},
					genre	=> $tags{g},
					comment	=> $tags{c},
				);
			} else {
				if($songinfo eq '0 @') { # No song info returned by plugin, this string is hard coded into Musicus for this case
					$title = '';
				} else {
					# We capture the space because it's part of the record seperator if we do get a title string.  If we don't then there's a space tacked on to the beginning of the title, so it must be removed.
					$title =~ s/^ //;
				}

				# Go ahead and fill out the hash
				%info = (
					%info,
					artist	=> '',
					title	=> $title,
					album	=> '',
					track	=> '',
					year	=> '',
					date	=> '',
					genre	=> '',
					comment	=> '',
				);
			}

			POE::Kernel->post($self->{alias}, $self->{$command}, \%info);
		} elsif (/^\@ ERROR (.*?)\s*"(.*?)"\s*$/) {
			POE::Kernel->post($self->{alias}, $self->{error}, $self, { err => -1, error => $2, syscall => $1 });
		}
	};

	my $self = $class->SUPER::new(
		events		=> { stdout => $stdout, @events },
		writemap	=> $writemap,
		debug		=> $params{debug},
	);

	%$self = (%$self, %params); # Add my paramaters to the hash that gets passed around

	$self->start();

	return $self;
}

sub start {
	my $self = shift;
	
	$self->run($self->{musicus}, '-path', $self->{path}, '-output', $self->{output});
}

sub play {
	my ($self, $file) = @_;
	$file =~ s/"/\\"/g; # Escape quotes for Musicus
	$self->write("play \"$file\"");
}
sub getinfo {
	my ($self, $file) = @_;
	$file =~ s/"/\\"/g; # Escape quotes for Musicus
	$self->write("getinfo \"$file\"");
}

sub setvol {
	my ($self, $left, $right) = @_;
	$self->write("setvol $left $right");
}

sub setpos {
	my ($self, $pos) = @_;
	$self->write("setpos $pos");
}

sub xcmd {
	my ($self, $cmd) = @_;
	return -1 unless $cmd;
	$self->write($cmd);
}

1;

__END__

=head1 NAME

POE::Component::Player::Musicus - a POE wrapper for the B<musicus> audio player

=head1 SYNOPSIS

	use POE qw(Component::Player::Musicus);

	$musicus = POE::Component::Player::Musicus->new();
	$musicus->play("test.mp3");

	POE::Kernel->run();

=head1 DESCRIPTION

This POE component is used to manipulate the B<musicus> player from within a POE application.

=head1 REQUIREMENTS

=over

=item * L<POE>

=item * L<POE::Component::Child>

=item * L<Text::Balanced>

=item * B<musicus> (1.11 or later) - L<http://muth.org/Robert/Musicus/>

=back

=head1 METHODS

An object oriented interface is provided as follows: 

=head2 new %hash

Used to initialise the system and create a module instance.  The optional hash may contain any of the following keys:

=over 

=item alias

Indicates the name of a session to which events will be posted.  Default: I<main>.

=item path

Path to your XMMS plugins.  Default: F</usr/lib/xmms>.

=item output

Output plugin.  Default: F<libOSS.so>.

=item musicus

Location of musicus executable.  Default: F<musicus>.

=item <event-name>

Any event fired by this module can be mapped to a name of choice.  This is useful for differentiating this component's events from some other component's e.g. C<< done => "musicus_done" >> will cause the component to fire a I<musicus_done> event at the main session, instead of the usual I<done>.  For a comprehensive listing of events fired, please refer to the L</EVENTS> section below.

=back

=head2 start

This method starts the player.  While it should not be necessary to ever call this method directly since the C<new()> method calls it automatically, this method allows for restarting the player in such instances as when it dies.

=head2 play <path>

This method requires a single parameter specifying the full path name of an audio file to play.

=head2 quit stop pause unpause

None of these methods take any parameters and will do exactly as their name implies.

=head2 getpos

Tells Musicus to send back the current position.  Will cause a L</getpos> event to fire.

=head2 getinfocurr

Tells Musicus to send back the current song information.  Will cause a L</getinfocurr> event to fire.

=head2 getinfo <file>

Tells Musicus to send back information about the file specified.  Will cause a L</getinfo> event to fire.

=head2 getlength

Tells Musicus to send back the length of the current file.  Will cause a L</getlength> event to fire.

=head2 getvol

Tells Musicus to send back the current volume.  Will cause a L</getvol> event to fire.

=head2 version

Tells Musicus to send back its version string.  Will cause a L</version> event to fire.

=head2 setvol <integer> <integer>

Causes Musicus to set the left and right channel volume to the numbers specified.  Will cause a L</setvol> event to fire.

=head2 setpos <integer>

Causes Musicus to jump to the specified location in the file.

=head2 xcmd <string>

This method allows for the sending of arbitrary commands to the player in the unlikely case that this component doesn't support something you want to do.

=head1 EVENTS

Events are fired at the session as configured in the L<new|/"new %hash"> method by I<alias>.  The names of the event handlers may be changed from their defaults by using they name of the event listed below as they key and the name of the event you want it to be called as the value in the L<new|/"new %hash">.

=head2 ready

Fired when the player has successfully started.  You do not need to wait for this event to start sending commands.

=head2 done / died

Fired upon termination or abnormal ending of the player.  This event is inherited from L<POE::Component::Child>, see those docs for more details.

=head2 error

Fired upon encountering an error.  This includes not only errors generated during execution of the player but also generated by the player itself in an interactive basis i.e. any C<@ ERROR> lines generated on stderr by the process.  For parameter reference please see L<POE::Component::Child> documentation, with the following caveat: for C<@ ERROR> type errors, I<err> is set to -1, I<syscall> is set to the command type that failed, and I<error> contains the player error string.

=head2 stop pause unpause

These events are fired whenever any of the named actions occur.

=head2 quit

These event is fired when the player has received the quit command and is about to exit.

=head2 version

Fired after the L</version> method is called, first argument is the Musicus version string.

=head2 setvol

Fired after a successful L</setvol> call.

=head2 play

Fired after a song has been loaded, first argument is the input plugin that will be used to play it.  Note that Musicus doesn't check to make sure it can play the file before returning this, it would probably be best to call L</getpos> after you get this event to make sure that the song actually started playing.

=head2 getpos

Fired after a successful L</getpos> call, first argument is the position in the file.

=head2 getinfocurr

Fired after a successful L</getinfocurr> call, first argument is a hashref with the following keys: I<file>, I<length>, I<artist>, I<title>, I<album>, I<track>, I<year>, I<date>, I<genre>, and I<comment>.  The I<file> value is the same as the argument that was supplied to L</play>.

=head2 getinfo

Fired after a successful L</getinfo> call.  The format is the same as L</getinfocurr>.  The I<file> value is the same as the argument supplied to the L</getinfo> method.

=head2 setpos

Fired after a successful L</setpos>, first argument is the position playback has been set to.

=head2 getlength

Fired after a successful L</getlength>, first argument is the length of the audio file. 

=head1 AUTHOR

Curtis "Mr_Person" Hawthorne <mrperson@cpan.org>

=head1 BUGS

=over

=item * If the XMMS MAD plugin is used, Musicus may mysteriously die on a L</getinfocurr> command.  I have no idea why this happens and help would be appreciated.

=back

=head1 ACKNOWLEDGEMENTS

This component is based on L<POE::Component::Player::Mpg123> by Erick Calder, which is distributed under the MIT License.

Development would not have been possible without the generous help of Robert Muth, creator of Musicus (L<http://www.muth.org/Robert/>).

Some ideas for the getinfo/getinfocurr processing were taken from a patch submitted by Mike Schilli (L<http://www.perlmeister.com>).

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2004 Curtis "Mr_Person" Hawthorne. This product is distributed under the MIT License. A copy of this license was included in a file called LICENSE. If for some reason, this file was not included, please see L<http://www.opensource.org/licenses/mit-license.html> to obtain a copy of this license.

