#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use lib '../..';

use Carbon2;
use Carbon::TCPReceiver;
use Carbon::HTTP::Connection;
use Carbon::Router;
use Carbon::HTTP::Response;

use Data::Dumper;


=pod

an example server with some simple routing and logic to display a form and receive the input of the submitted form

=cut


my $rtr = Carbon::Router->new;

# index page
$rtr->route( qr!/! => sub {
	my ($rtr, $req, $res) = @_;

	$res //= Carbon::HTTP::Response->new;
	$res->code('200');
	$res->header('content-type' => 'text/html');
	$res->content('<!doctype html>
<html>
	<body>
		<form method="POST" action="post">
			<input type="text" name="test" />
			<input type="password" name="password" />
			<input type="hidden" name="SUPER SECRET" value="-42" />
			<button>submit</button>
		</form>
	</body>
</html>
');
	$res->header('content-length' => length $res->content);
	
	return $res
});
# post receiver
$rtr->route( qr!/post! => sub {
	my ($rtr, $req, $res) = @_;

	$res //= Carbon::HTTP::Response->new('200');
	$res->content("you sent: " . ($req->content // ''));
	$res->header('content-length' => length $res->content);
	
	return $res
});

# default path
$rtr->default_route(sub {
	my ($rtr, $req, $res) = @_;

	# make a custom 404 response
	$res = Carbon::HTTP::Response->new('404');
	$res->content('THIS IS NOT A VALID PATH!');
	$res->header('content-length' => length $res->content);

	return $res
});

my $svr = Carbon2->new(
	debug => 1,
	receivers => [
		Carbon::TCPReceiver->new(2048 => 'Carbon::HTTP::Connection'),
	],
	processors => {
		'http:' => $rtr,
	},
);

$SIG{INT} = sub {
	$svr->shutdown;
};

$svr->start;

