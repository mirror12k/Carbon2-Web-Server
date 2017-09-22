#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use Carbon2;
use Carbon::TCPReceiver;
use Carbon::HTTP::Connection;
use Carbon::Router;
use Carbon::HTTP::ReverseProxy;
use Carbon::HTTP::FileServer;

use Data::Dumper;

use IO::Socket::INET;
use IO::Select;



my $svr = Carbon2->new(
	debug => 1,
	receivers => [
		Carbon::TCPReceiver->new(2048 => 'Carbon::HTTP::Connection'),
	],
	processors => {
		'http:' => Carbon::HTTP::ReverseProxy->new
			->route_reverse_proxy(qr/\/.*/ => '192.168.11.3:80'),
	},
);

$SIG{INT} = sub {
	$svr->shutdown;
};

$svr->start;
