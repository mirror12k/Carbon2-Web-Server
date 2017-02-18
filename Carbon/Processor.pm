package Carbon::Processor;
use strict;
use warnings;

use feature 'say';



sub new {
	my ($class) = @_;
	my $self = bless {}, $class;

	return $self
}

sub execute_gpc {
	my ($self, $gpc) = @_;
	die "unimplemented ->execute_gpc callback in $self"
}

# optional callback called upon a new processing thread starting
sub init_thread {}

1;
