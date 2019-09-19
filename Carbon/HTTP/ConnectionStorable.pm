package Carbon::HTTP::Connection;
use parent 'Carbon::Connection';
use strict;
use warnings;

use feature 'say';

use Carbon::HTTP::Request;
use Carbon::URI;

use Sugar::IO::Dir;

use Data::Dumper;

sub new {
	my ($class, $server, $socket, %args) = @_;
	my $self = $class->SUPER::new($server, $socket, %args);

	$self->{limit_memory_upload} = $args{limit_memory_upload} // (1024 * 1024 * 128);
	$self->{temp_file_directory} = defined $args{temp_file_directory} ? Sugar::IO::Dir->new($args{temp_file_directory}) : undef;

	return $self
}

sub on_data {
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

				$self->on_http_header;
			# }
		}
	}

	# if it has completed the header transfer
	if (defined $self->{http_request}) {
		my $req = $self->{http_request};

		if (defined $req->header('content-length')) { # if it has a content-length
			say "debug content-length: ", length $self->{buffer}, " of ", int $req->header('content-length');

			# check if we have a temp file for storage
			if (defined $self->{temp_file_directory} and ref ($req->content) eq "Sugar::IO::File") {

				my $file_size = $req->content->size // 0;

				say "debug file storage: ", $file_size, " + ", length($self->{buffer}),
					" of ", int $req->header('content-length');

				# check if we are done loading the data
				if ($file_size + length ($self->{buffer}) >= $req->header('content-length')) {
					my $length = $req->header('content-length') - $file_size;
					$req->content->append(substr $self->{buffer}, 0, $length);
					$self->{buffer} = substr $self->{buffer}, $length;

					# say "debug got request: ", $req->as_string;
					$self->{http_request} = undef;
					$self->on_http_request($req);
				} else {
					# otherwise just store the buffer on disk
					$req->content->append($self->{buffer});
					$self->{buffer} = '';
				}

			# check if the whole body has arrived for memory storage
			} elsif (length ($self->{buffer}) >= $req->header('content-length')) {
				# set the request content
				$req->content(substr $self->{buffer}, 0, $req->header('content-length'));
				$self->{buffer} = substr $self->{buffer}, $req->header('content-length');

				# start the job
				# say "debug got request: ", $req->as_string;
				$self->{http_request} = undef;
				$self->on_http_request($req);
			}
		} else {
			# if there is no body, start the job immediately
			# say "debug got request: ", $req->as_string;
			$self->{http_request} = undef;
			$self->on_http_request($req);
		}
	}
}

sub parse_http_header {
	my ($self, $data) = @_;
	my $req = Carbon::HTTP::Request->parse($data);

	if (defined $req) {
		$req->uri(Carbon::URI->parse($req->uri));
	}

	return $req
}

sub on_result {
	my ($self, $response) = @_;
	$response = $response // Carbon::HTTP::Response->new(
		404,
		'Not Found',
		{ 'content-length' => [ length 'Not Found' ] },
		'Not Found'
	);
	my $body = $response->content;
	if (ref $body eq 'HASH' and exists $body->{filepath}) {
		$response->content(undef);
		$self->write_to_output_buffer($response->as_string);
		$self->write_file_to_output_buffer($body->{filepath});
	} else {
		$self->write_to_output_buffer($response->as_string);
	}
	# $self->write_buffered($response->as_string);
	# $self->{socket}->print($response->as_string);
}

sub on_http_header {
	my ($self) = @_;

	my $req = $self->{http_request};

	# destroy own connection if request parsing failed
	if (not defined $req) {
		$self->remove_self;
		return;
	}

	# check excessive upload size
	if ($self->{limit_memory_upload} >= 0 and defined $req->header('content-length')
			and $req->header('content-length') > $self->{limit_memory_upload}) {

		if (defined $self->{temp_file_directory}) {
			# if we have a temporary directory where to store files, write it there
			my $temp_file = $self->{temp_file_directory}->temp_file;
			$req->content($temp_file);
		} else {
			# otherwise send an error response
			$self->{server}->warn(5, "oversized request of size " . int($req->header('content-length')) . " sent, rejecting");

			my $res = Carbon::HTTP::Response->new(
				413,
				'Payload Too Large',
				{ 'content-length' => [ length 'Payload Too Large' ] },
				'Payload Too Large'
			);
			$self->{http_request} = undef;
			$self->on_result($res);

			return;
		}

	}
}

sub on_http_request {
	my ($self, $req) = @_;
	$self->produce_gpc(format_gpc($req));
}

sub format_gpc {
	my ($req) = @_;

	my $uri = $req->uri->clone;
	$uri->protocol('http:');
	return { uri => $uri, data => $req }
}

1;
