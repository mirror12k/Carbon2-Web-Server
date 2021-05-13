package Carbon::HTTP::JSONServer;
use parent 'Carbon::Router';
use strict;
use warnings;

use feature 'say';

use Carp;
use JSON;

use Carbon::HTTP::Response;



sub route_json {
	my ($self, $path, $callback, %opts) = @_;

	return $self->route(qr/$path.*/ => sub {
		my ($self, $req) = @_;
		my $json_res = $callback->($self, decode_json($req->content), $req);

		my $res = Carbon::HTTP::Response->new('200', 'OK');
		$res->content(encode_json($json_res));
		$res->header('content-length' => length $res->content);
		$res->header('content-type' => 'application/json');

		return $res;
	}, %opts);
}



1;
