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

	my $route = { regex => $path, callbacks => $callback, options => $opts };
	push @{$self->{routes}}, $route;

	# $self->warn($CARBON_FIBER_DEBUG_VALUE, "added route for path $path");

	return $self
}

sub default_route {
	my ($self, $callback, $opts) = @_;

	$callback = ref $callback eq 'ARRAY' ? [ @$callback ] : [ $callback ];
	$self->{default_route} = { callbacks => $callback, options => $opts };

	return $self
}

sub execute_gpc {
	my ($self, $gpc) = @_;

	my $uri = $gpc->{uri};
	my $req = $gpc->{data};
	my @results;

	for my $route (@{$self->{routes}}) {
		if ($uri->path =~ $route->{regex}) {
			for my $callback (@{$route->{callbacks}}) {
				if (ref $callback eq 'CODE') {
					@results = $callback->($self, $req, @results);
				} else {
					@results = $callback->execute_gpc($gpc);
				}
			}
		}
	}
	unless (@results) {
		for my $callback (@{$self->{default_route}{callbacks}}) {
			@results = $callback->($self, $req, @results);
		}
	}

	return @results
}

1;
