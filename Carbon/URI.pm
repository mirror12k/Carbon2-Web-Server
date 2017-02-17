package Carbon::URI;
use strict;
use warnings;

use feature 'say';


sub new ($$) {
	my ($class) = @_;
	my $self = bless {}, $class;

	return $self
}

sub parse {
	my ($self, $uri) = @_;
	$self = $self->new unless ref $self;

	return unless $uri =~ m!\A
			(?:(?:([^/?#]*:))?//([^/?#:]++)(?::(\d+))?)?
			([^?#]*?)
			(?:\?([^#]*?))?
			(?:\#(.*))?
			\Z!x;
	$self->protocol($1);
	$self->host($2);
	$self->port($3);
	$self->path($4);
	$self->query($5);
	$self->fragment($6);

	return $self
}

sub protocol { @_ > 1 ? $_[0]{protocol} = $_[1] : $_[0]{protocol} }
sub host { @_ > 1 ? $_[0]{host} = $_[1] : $_[0]{host} }
sub port { @_ > 1 ? $_[0]{port} = $_[1] : $_[0]{port} }
sub path { @_ > 1 ? $_[0]{path} = $_[1] : $_[0]{path} }
sub query { @_ > 1 ? $_[0]{query} = $_[1] : $_[0]{query} }
sub fragment { @_ > 1 ? $_[0]{fragment} = $_[1] : $_[0]{fragment} }



sub query_form {
	my ($self) = @_;
	return {} unless defined $self->query;
	return { map { ($_->[0] // '') => ($_->[1] // '') } map [split('=', $_, 2)], split '&', $self->query }
}

sub as_string {
	my ($self) = @_;
	my $uri = '';
	$uri .= $self->{protocol} . '//' if defined $self->{protocol};
	$uri .= $self->{host} if defined $self->{host};
	$uri .= ':' . $self->{port} if defined $self->{port};
	$uri .= $self->{path} if defined $self->{path};
	$uri .= '?' . $self->{query} if defined $self->{query};
	$uri .= '#' . $self->{fragment} if defined $self->{fragment};
	return $uri
}

sub dump {
	my ($self) = @_;

	say "protocol: ", $self->protocol // '';
	say "host: ", $self->host // '';
	say "port: ", $self->port // '';
	say "path: ", $self->path // '';
	say "query: ", $self->query // '';
	say "fragment: ", $self->fragment // '';
}



# Carbon::URI->parse("/asdf?quryu")->dump;
# Carbon::URI->parse("localhost:2048/asdf?quryu")->dump;
# Carbon::URI->parse("http://google.com/asdf?quryu")->dump;
# Carbon::URI->parse("/babble#ref")->dump;

1
