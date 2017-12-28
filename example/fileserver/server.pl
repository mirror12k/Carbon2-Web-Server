#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use lib '../..';

use Carbon2;
use Carbon::TCPReceiver;
use Carbon::HTTP::Connection;
use Carbon::HTTP::FileServer;

use Data::Dumper;





my $svr = Carbon2->new(
	debug => 1,
	receivers => [
		Carbon::TCPReceiver->new(2048 => 'Carbon::HTTP::Connection'),
	],
	processors => {
		'http:' => Carbon::HTTP::FileServer->new
			->route_directory('/' => shift // '.'),
	},
);

$SIG{INT} = sub {
	$svr->shutdown;
};

$svr->start;
