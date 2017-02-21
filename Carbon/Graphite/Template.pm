package Carbon::Graphite::Template;
use strict;
use warnings;

use feature 'say';




sub new {
	my ($class, $code) = @_;
	my $self = bless {}, $class;

	$self->code_ref($code);

	return $self
}

sub code_ref { @_ > 1 ? $_[0]{graphite_template__code_ref} = $_[1] : $_[0]{graphite_template__code_ref} }


sub execute {
	my ($self, $graphite, $arg) = @_;
	return $self->code_ref->($self, $graphite, $arg)
}



1;
