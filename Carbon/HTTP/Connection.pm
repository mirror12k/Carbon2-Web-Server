package Carbon::HTTP::Connection;
use parent 'Carbon::Connection';
use strict;
use warnings;

use feature 'say';

use Carbon::HTTP::Request;
use Carbon::URI;

use Data::Dumper;



sub new {
	my ($class, $fd) = @_;
	my $socket = IO::Socket::INET->new;
	$socket->fdopen($fd, 'r+'); # 'rw' stalls
	return $class->SUPER::new($socket)
}

sub produce_gpc {
	my ($self) = @_;

	# if there is no request for this socket yet
	unless (defined $self->{http_request}) {
		# otherwise check if it's ready for header processing
		if ($self->{buffer} =~ /\r\n\r\n/) {
			my ($header, $body) = split /\r\n\r\n/, $self->{buffer}, 2;
			my $req = $self->parse_http_header($header);

			# if (not defined $req) {
			# 	# if the request processing failed, it means that it was an invalid request
			# 	$self->delete_socket($fh);
			# } else {
				$self->{http_request} = $req;
				$self->{buffer} = $body;
			# }
		}
	}

	# if it has completed the header transfer
	if (defined $self->{http_request}) {
		my $req = $self->{http_request};

		if (defined $req->header('content-length')) { # if it has a content-length
			# check if the whole body has arrived yet
			if ($self->{http_request}->header('content-length') <= length $self->{buffer}) {
				# set the request content
				$req->content(substr $self->{buffer}, 0, $self->{http_request}->header('content-length'));
				$self->{buffer} = substr $self->{buffer}, $self->{http_request}->header('content-length');

				# start the job
				# say "debug got request: ", $req->as_string;
				$self->{http_request} = undef;
				return format_gpc($req)
			}
		} else {
			# if there is no body, start the job immediately
			# say "debug got request: ", $req->as_string;
			$self->{http_request} = undef;
			return format_gpc($req)
		}
	}
	return
}

sub parse_http_header {
	my ($self, $data) = @_;
	my $req = Carbon::HTTP::Request->parse($data);

	if (defined $req) {
		$req->uri(Carbon::URI->parse($req->uri));
	}

	return $req
}

sub response {
	my ($self, $res) = @_;
	# say "got result: ", Dumper $res;
	$self->{socket}->print($res->as_string);
}

sub format_gpc {
	my ($req) = @_;

	my $uri = $req->uri->clone;
	$uri->protocol('http:');
	return { uri => $uri, data => $req }
}

1;
