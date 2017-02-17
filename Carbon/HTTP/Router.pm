package Carbon::HTTP::Router;
use parent 'Carbon::Router';
use strict;
use warnings;

use feature 'say';

use Carbon::HTTP::Request;
use Carbon::HTTP::Response;

use Data::Dumper;


sub protocol { qw/ http: https: / }

sub route {
	my ($self, $gpc) = @_;
	# say "got gpc ", Dumper $gpc;

	my $data = Dumper $gpc;
	return Carbon::HTTP::Response->new(200, 'OK', { 'content-length' => [length $data] }, $data)
}

1;
