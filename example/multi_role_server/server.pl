#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use lib '../..';

use Carbon2;
use Carbon::TCPReceiver;
use Carbon::HTTP::Connection;
use Carbon::Router;
use Carbon::HTTP::FileServer;

use Data::Dumper;





my $svr = Carbon2->new(
	debug => 1,
	receivers => [
		Carbon::TCPReceiver->new(2048 => 'Carbon::HTTP::Connection'),
	],
	processors => {
		'http:' => Carbon::Router->new
			->route('/' => sub {
					my $res = Carbon::HTTP::Response->new('200', 'OK');
					$res->content('<!doctype html><html><body>
						<p>hello world!</p>
						<p>you can find my dynamic script <a href="/dynamic">over here</a></p>
						<p>you can find my file server <a href="/files/">over here</a></p>
					</body></html>');
					$res->header('content-length' => length $res->content);
					$res->header('content-type' => 'text/html');
					return $res
				})
			->route('/dynamic' => sub {
					my ($rtr, $req) = @_;
					my $res = Carbon::HTTP::Response->new('200', 'OK');
					$res->content("hello world, your request looked like this: " . $req->as_string);
					$res->header('content-length' => length $res->content);
					$res->header('content-type' => 'text/plain');
					return $res
				})
			->route(qr#/files/.*# => Carbon::HTTP::FileServer->new->route_directory('/files/' => '.')),
	},
);

$SIG{INT} = sub {
	$svr->shutdown;
};

$svr->start;
