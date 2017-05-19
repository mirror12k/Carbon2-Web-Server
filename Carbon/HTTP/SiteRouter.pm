package Carbon::HTTP::SiteRouter;
use parent 'Carbon::Processor';

use strict;
use warnings;

use feature 'say';

use Carp;

use Data::Dumper;



sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{sites} = $args->{sites};

	return $self
}

sub init_thread {
	my ($self, $server) = @_;
	foreach my $sub_router (values %{$self->{sites}}) {
		$sub_router->init_thread($server);
	}
}

sub execute_gpc {
	my ($self, $gpc) = @_;

	my $uri = $gpc->{uri};
	my $req = $gpc->{data};

	my $host = lc $req->header('host');

	my @results;
	for my $site (keys %{$self->{sites}}) {
		if ($host eq lc $site) {
			@results = $self->{sites}{$host}->execute_gpc($gpc);
			last
		}
	}

	return @results
}

1;
