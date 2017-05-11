#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use lib '../..';

use Carbon2;
use Carbon::TCPReceiver;
use Carbon::HTTP::Connection;
use Carbon::HTTP::StorageServer;

use Data::Dumper;



mkdir 'store';

my $svr = Carbon2->new(
	debug => 1,
	receivers => [
		Carbon::TCPReceiver->new(2048 => 'Carbon::HTTP::Connection'),
	],
	processors => {
		'http:' => Carbon::HTTP::StorageServer->new
			->route_storage('/' => 'store', permission => 'permission.json', jail_users => 1)
	},
);

$SIG{INT} = sub {
	$svr->shutdown;
};

$svr->start;


