package Carbon::Anthracite::CompiledFile;
use strict;
use warnings;

sub new ($) {
	my ($class) = @_;
	my $self = bless {}, $class;
	return $self
}

sub code { @_ > 1 ? $_[0]{carbon_anthracite_compiledfile__code} = $_[1] : $_[0]{carbon_anthracite_compiledfile__code} }
sub router { @_ > 1 ? $_[0]{carbon_anthracite_compiledfile__router} = $_[1] : $_[0]{carbon_anthracite_compiledfile__router} }
sub filepath { @_ > 1 ? $_[0]{carbon_anthracite_compiledfile__filepath} = $_[1] : $_[0]{carbon_anthracite_compiledfile__filepath} }




1;

