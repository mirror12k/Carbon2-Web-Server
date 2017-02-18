package Carbon::Fiber;
use parent 'Carbon::Router';

use strict;
use warnings;

use feature 'say';

use Carp;

use Data::Dumper;



sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{routes} = [];

	return $self
}

sub route {
	my ($self, $path, $method, $opts) = @_;
	$opts //= {};

	$method = ref $method eq 'ARRAY' ? [@$method] : [$method];
	$path = quotemeta $path unless ref $path eq 'Regexp';
	$path = qr/\A$path\Z/;

	my $route = { regex => $path, functions => $method, options => $opts };
	push @{$self->{routes}}, $route;

	# $self->warn($CARBON_FIBER_DEBUG_VALUE, "added route for path $path");

	return $self
}

sub execute_gpc {
	my ($self, $gpc) = @_;
	my $req = $gpc->{data};
	my $res;
	for my $route (@{$self->{routes}}) {
		if ($req->uri->path =~ $route->{regex}) {
			$res = $_->($self, $req, $res) for @{$route->{functions}};
		}
	}
	$res = Carbon::HTTP::Response->new(404, 'Not Found', { 'content-length' => [length 'Not Found'] }, 'Not Found') unless defined $res;
	return $res
}

1;
