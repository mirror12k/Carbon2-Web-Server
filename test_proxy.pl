#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

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
			->route(qr#/.*# => sub {
					my ($rtr, $req) = @_;
					my $uri = $req->uri;
					$req->uri($uri->as_string);
					# say "got request: ", $req->as_string;

					my $socket = IO::Socket::INET->new(
						PeerAddr => "192.168.11.3:80",
						Proto => "tcp",
					);

					if (!$socket) {
						my $res = Carbon::HTTP::Response->new('500', 'Server Connection Error');
						$res->content("failed to connect to remote: " . $@);
						$res->header('content-length' => length $res->content);
						$res->header('content-type' => 'text/plain');

						return $res;
					}

					$socket->print($req->as_string);

					my $buf = '';
					$socket->read($buf, 4096 / 16, length $buf) until $buf =~ /\r\n\r\n/s;

					my ($header, $content) = split /\r\n\r\n/s, $buf, 2;

					my $remote_res = Carbon::HTTP::Response->parse($buf);
					if ($remote_res->headers->{'content-length'}) {
						my $content_length = abs int $remote_res->headers->{'content-length'}[0];
						while (length $content < $content_length) {
							$socket->read($content, $content_length - length $content, length $content);
						}
						$remote_res->content($content);
					}

					$socket->close;
					# say "got response: ", $buf;
					return $remote_res
				}),
	},
);

$SIG{INT} = sub {
	$svr->shutdown;
};

$svr->start;
