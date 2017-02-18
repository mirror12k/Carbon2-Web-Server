package Carbon::Router;
use parent 'Carbon::Processor';

use strict;
use warnings;

use feature 'say';

use Carp;

use Data::Dumper;



sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{routes} = [];
	$self->{default_route} = undef;

	return $self
}

sub route {
	my ($self, $path, $callback, $opts) = @_;
	$opts //= {};

	$callback = ref $callback eq 'ARRAY' ? [ @$callback ] : [ $callback ];
	$path = quotemeta $path unless ref $path eq 'Regexp';
	$path = qr/\A$path\Z/;

	my $route = { regex => $path, functions => $callback, options => $opts };
	push @{$self->{routes}}, $route;

	# $self->warn($CARBON_FIBER_DEBUG_VALUE, "added route for path $path");

	return $self
}

sub default_route {
	my ($self, $callback, $opts) = @_;

	$callback = ref $callback eq 'ARRAY' ? [ @$callback ] : [ $callback ];
	$self->{default_route} = { functions => $callback, options => $opts };

	return $self
}

sub execute_gpc {
	my ($self, $gpc) = @_;

	my $uri = $gpc->{uri};
	my $req = $gpc->{data};
	my @results;

	for my $route (@{$self->{routes}}) {
		if ($uri->path =~ $route->{regex}) {
			@results = $_->($self, $req, @results) for @{$route->{functions}};
		}
	}
	unless (@results) {
		@results = $_->($self, $req, @results) for @{$self->{default_route}{functions}};
	}

	return @results
}

1;
