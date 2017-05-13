package Carbon::Limestone::Query;
use strict;
use warnings;

use feature 'say';



sub new {
	my ($class, %args) = @_;
	my $self = bless { %args }, $class;

	return $self
}

1;
