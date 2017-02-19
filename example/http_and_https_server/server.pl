#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use lib '../..';

use Carbon2;
use Carbon::TCPReceiver;
use Carbon::SSLReceiver;
use Carbon::HTTP::Connection;
use Carbon::HTTP::FileServer;

use Data::Dumper;



die 'please run generate_certificate.sh to generate the ssl certificate for the server' unless -e 'cert.pem';

my $svr = Carbon2->new(
	debug => 1,
	receivers => [
		Carbon::TCPReceiver->new(2048 => 'Carbon::HTTP::Connection'),
		Carbon::SSLReceiver->new(2047 => 'Carbon::HTTP::Connection', ssl_certificate => 'cert.pem', ssl_key => 'key.pem'),
	],
	processors => {
		'http:' => Carbon::HTTP::FileServer->new
			->route_directory('/' => '.')
	},
);

$SIG{INT} = sub {
	$svr->shutdown;
};

$svr->start;


