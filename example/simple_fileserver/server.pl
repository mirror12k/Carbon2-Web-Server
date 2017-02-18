#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use lib '../..';

use Carbon2;
use Carbon::HTTP::FileServer;

use Data::Dumper;





my $svr = Carbon2->new(
	debug => 1,
	processors => {
		'http:' => Carbon::HTTP::FileServer->new
			->route_directory('/' => '.'),
	},
);

$SIG{INT} = sub {
	$svr->shutdown;
};

$svr->start;
