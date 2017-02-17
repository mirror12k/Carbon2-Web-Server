package Carbon::Router;
use strict;
use warnings;

use feature 'say';



sub new {
	my ($class) = @_;
	my $self = bless {}, $class;

	return $self
}

sub route {
	my ($self, $gpc) = @_;
	die "unimplemented ->route callback in $self"
}

# optional callback called upon a new processing thread starting
sub init_thread {}

1;
