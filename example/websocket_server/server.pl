#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use lib '../..';

use Carbon2;
use Carbon::TCPReceiver;
use Carbon::HTTP::Connection;
use Carbon::WebSocket::HTTPPromoter;

use Carbon::WebSocket::Processor;
use Carbon::HTTP::FileServer;




=pod

an example websocket server which recieves websocket connections at ws://localhost:2049/ and responds with basic text responses

=cut

my $svr = Carbon2->new(
	debug => 1,
	receivers => [
		# an http server to serve our index page
		Carbon::TCPReceiver->new(2048 => 'Carbon::HTTP::Connection'),
		# a websocket server to receive and serve websocket connections from our index page
		Carbon::TCPReceiver->new(2047 => 'Carbon::WebSocket::HTTPPromoter'),
	],
	processors => {
		# http requests go to a file server
		'http:' => Carbon::HTTP::FileServer->new
			->route_directory('/' => '.', default_file => 'index.html'),
		# websocket requests get handled here
		'ws:' => Carbon::WebSocket::Processor->new(paths => {
			'/' => {
				text => sub {
					my ($con, $text) = @_;
					if ($text ne '') {
						$con->send("hello there: $text");
						$con->send("i am: a big bear");
					} else {
						$con->close;
					}
				}
			},
			'/story' => {
				connected => sub {
					my ($con) = @_;
					$con->session->{index} = 0;
					$con->send("hello dear reader, would you like a story?");
				},
				text => sub {
					my ($con, $text) = @_;
					my $index = $con->session->{index} // 0;

					my @story = (
						'the quick brown fox',
						'jumped',
						'over the lazy dog',
					);

					if ($index <= $#story) {
						$con->send("$story[$index]");
						$con->session->{index}++;
					} else {
						$con->close;
						$con->session->{closed_by_server} = 1;
					}

				},
				disconnected => sub {
					my ($con) = @_;
					if ($con->session->{closed_by_server}) {
						say "the server closed the connection!";
					} else {
						say "the reader disconnected!";
					}
				},
			},
		}),
	},
);

$SIG{INT} = sub {
	$svr->shutdown;
};

$svr->start;
