package Carbon::Graphite::Helper;
use strict;
use warnings;

use feature 'say';




sub new {
	my ($class, $code) = @_;
	my $self = bless {}, $class;

	$self->code_ref($code);

	return $self
}

sub code_ref { @_ > 1 ? $_[0]{graphite_helper__code_ref} = $_[1] : $_[0]{graphite_helper__code_ref} }


sub execute {
	my ($self, $engine, $text) = @_;
	$self->code_ref->($self, $engine, $text);
}



1;
