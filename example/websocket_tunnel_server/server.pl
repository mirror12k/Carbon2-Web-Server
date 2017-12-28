#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use lib '../..';

use Carbon2;
use Carbon::TCPReceiver;
use Carbon::HTTP::Connection;
use Carbon::HTTP::FileServer;
use Carbon::WebSocket::HTTPPromoter;
use Carbon::WebSocket::TunnelProcessor;
use Carbon::Limestone;

use Data::Dumper;



# internal database
my $database = Carbon::Limestone->new(debug => 1);

# execute a create query to make a memory database
my $res = $database->execute_gpc({
	uri => Carbon::URI->parse('/my_memory_db'),
	data => Carbon::Limestone::Query->new(method => 'create', database_type => 'Carbon::Limestone::MemoryDatabase'),
});
say Dumper $res;



my $svr = Carbon2->new(
	debug => 1,
	receivers => [
		# http server at http://localhost:2048/ to serve index.html
		Carbon::TCPReceiver->new(2048 => 'Carbon::HTTP::Connection'),
		# websocket server at ws://localhost:2047/ to tunnel limestone requests
		Carbon::TCPReceiver->new(2047 => 'Carbon::WebSocket::HTTPPromoter'),
	],
	processors => {
		'http:' => Carbon::HTTP::FileServer->new
			->route_directory('/' => '.', default_file => 'index.html'),
		# the limestone database receives limestone requests over a websocket tunnel
		'ws:' => Carbon::WebSocket::TunnelProcessor->new(
				processor => $database),
	},
);

$SIG{INT} = sub {
	$svr->shutdown;
	$database->store_databases;
};

$svr->start;
