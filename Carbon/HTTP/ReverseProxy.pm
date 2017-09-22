package Carbon::HTTP::ReverseProxy;
use parent 'Carbon::Router';
use strict;
use warnings;

use feature 'say';

use Carp;

use Carbon::HTTP::Response;





sub new {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new(%args);

	return $self
}

sub route_reverse_proxy {
	my ($self, $path, $remote_address, %opts) = @_;
	croak 'remote_address option required' unless defined $remote_address; # "ip:port" of remote server

	return $self->route(qr/$path.*/ => sub {
		my ($self, $req) = @_;

		return $self->execute_remote_request($remote_address, $req)
	}, %opts)
}

sub execute_remote_request {
	my ($self, $remote_address, $req) = @_;

	my $uri = $req->uri;
	$req->uri($uri->as_string);
	# $req->header('x-forwarded-for' => ) # TODO
	my $write_buffer = $req->as_string;
	$req->uri($uri);
	# say "got request: $write_buffer";

	# connect to remote server
	my $socket = IO::Socket::INET->new(
		PeerAddr => $remote_address,
		Proto => "tcp",
		Blocking => 0,
	);

	if (!$socket) {
		warn "failed to connect to remote: $@";

		my $res = Carbon::HTTP::Response->new('500', 'Server Connection Error');
		$res->content("failed to connect to remote");
		$res->header('content-length' => length $res->content);
		$res->header('content-type' => 'text/plain');

		return $res;
	}

	my $selector = IO::Select->new($socket);

	# write request to socket
	my $wrote_length = 0;
	while ($wrote_length < length $write_buffer) {
		last unless $selector->can_write(5);
		my $wrote = $socket->syswrite($write_buffer, length ($write_buffer) - $wrote_length, $wrote_length);
		# say "wrote: $wrote";
		$wrote_length += $wrote if defined $wrote and $wrote > 0;
	}

	if ($wrote_length < length $write_buffer) {
		warn "failed to write request to remote: $@";

		my $res = Carbon::HTTP::Response->new('500', 'Server Connection Timeout');
		$res->content("server timed out during sending");
		$res->header('content-length' => length $res->content);
		$res->header('content-type' => 'text/plain');

		return $res;
	}

	# read response header
	my $buf = '';
	while ($buf !~ /\r\n\r\n/s) {
		last unless $selector->can_read(5);
		my $read = $socket->sysread($buf, 16 * 4096, length $buf);
		# say "read: $read";
	}

	if ($buf !~ /\r\n\r\n/s) {
		warn "response timed out: $@";

		my $res = Carbon::HTTP::Response->new('500', 'Server Connection Timeout');
		$res->content("server timed out");
		$res->header('content-length' => length $res->content);
		$res->header('content-type' => 'text/plain');

		return $res;
	}

	my ($header, $content) = split /\r\n\r\n/s, $buf, 2;

	my $remote_res = Carbon::HTTP::Response->parse($buf);

	# read response body if it exists
	if (exists $remote_res->headers->{'content-length'}) {
		my $content_length = abs int $remote_res->headers->{'content-length'}[0];
		while (length ($content) < $content_length) {
			last unless $selector->can_read(5);
			my $read = $socket->sysread($content, $content_length - length $content, length $content);
			# say "read2: $read";
		}

		if (length ($content) < $content_length) {
			warn "response body timed out: $@";

			my $res = Carbon::HTTP::Response->new('500', 'Server Connection Timeout');
			$res->content("server timed out");
			$res->header('content-length' => length $res->content);
			$res->header('content-type' => 'text/plain');

			return $res;
		}

		$remote_res->content($content);
	}

	$socket->close;
	# say "got response: ", $buf;

	# return response
	return $remote_res
}




1;
