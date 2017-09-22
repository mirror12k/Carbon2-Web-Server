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

use IO::Socket::INET;
use IO::Select;



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
						Blocking => 0,
					);

					if (!$socket) {
						my $res = Carbon::HTTP::Response->new('500', 'Server Connection Error');
						$res->content("failed to connect to remote: " . $@);
						$res->header('content-length' => length $res->content);
						$res->header('content-type' => 'text/plain');

						return $res;
					}

					my $selector = IO::Select->new($socket);

					my $write_buffer = $req->as_string;
					my $wrote_length = 0;
					while ($wrote_length < length $write_buffer) {
						last unless $selector->can_write(5);
						my $wrote = $socket->syswrite($write_buffer, length ($write_buffer) - $wrote_length, $wrote_length);
						# say "wrote: $wrote";
						$wrote_length += $wrote if defined $wrote and $wrote > 0;
					}

					if ($wrote_length < length $write_buffer) {
						my $res = Carbon::HTTP::Response->new('500', 'Server Connection Timeout');
						$res->content("server timed out during sending");
						$res->header('content-length' => length $res->content);
						$res->header('content-type' => 'text/plain');

						return $res;
					}

					my $buf = '';
					while ($buf !~ /\r\n\r\n/s) {
						last unless $selector->can_read(5);
						my $read = $socket->sysread($buf, 16 * 4096, length $buf);
						# say "read: $read";
					}

					if ($buf !~ /\r\n\r\n/s) {
						my $res = Carbon::HTTP::Response->new('500', 'Server Connection Timeout');
						$res->content("server timed out");
						$res->header('content-length' => length $res->content);
						$res->header('content-type' => 'text/plain');

						return $res;
					}




					my ($header, $content) = split /\r\n\r\n/s, $buf, 2;

					my $remote_res = Carbon::HTTP::Response->parse($buf);
					if ($remote_res->headers->{'content-length'}) {
						my $content_length = abs int $remote_res->headers->{'content-length'}[0];
						while (length $content < $content_length) {
							$selector->can_read(5);
							my $read = $socket->sysread($content, $content_length - length $content, length $content);
							# say "read2: $read";
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
