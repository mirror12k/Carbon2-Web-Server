#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use lib '../..';

use Carbon2;
use Carbon::TCPReceiver;
use Carbon::WS::HTTPPromoter;

use Carbon::Router;




=pod

an example websocket server which recieves websocket connections at ws://localhost:2048/ and responds with basic text responses

=cut

my $svr = Carbon2->new(
	debug => 1,
	receivers => [
		Carbon::TCPReceiver->new(2048 => 'Carbon::WS::HTTPPromoter'),
	],
	processors => {
		'ws:' => Carbon::Router->new
			->route(qr!/! => sub {
				my ($rtr, $text) = @_;
				return [
					{ type => 'text', text => "hello there: $text" }
				]
			}),
	},
);

$SIG{INT} = sub {
	$svr->shutdown;
};

$svr->start;
