#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use lib '../..';

use Carbon2;
use Carbon::TCPReceiver;
use Carbon::SOCKS::SOCKS4aAcceptor;



my $svr = Carbon2->new(
	debug => 1,
	receivers => [
		Carbon::TCPReceiver->new(9050 => 'Carbon::SOCKS::SOCKS4aAcceptor'),
	],
	processors => {},
);

$SIG{INT} = sub {
	$svr->shutdown;
};

$svr->start;
