package Carbon::Limestone::Response;
use strict;
use warnings;

use feature 'say';



sub new {
	my ($class, %args) = @_;
	my $self = bless { %args }, $class;

	return $self
}

1;
