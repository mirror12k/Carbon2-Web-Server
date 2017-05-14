package Carbon::Limestone::ServerConnection;
use parent 'Carbon::Connection';
use strict;
use warnings;

use feature 'say';

use Data::Dumper;
use Gzip::Faster;
use JSON;

use Carbon::URI;
use Carbon::Limestone::Query;
use Carbon::Limestone::Response;



sub read_buffered {
	my ($self) = @_;

	$self->SUPER::read_buffered;


	while (length $self->{buffer} > 0) {

		# if there is no request length yet, try to read the request length
		unless (defined $self->{request_length}) {
			if (length $self->{buffer} >= 4) {
				$self->{request_length} = unpack 'N', substr $self->{buffer}, 0, 4;
				$self->{buffer} = substr $self->{buffer}, 4;
			}
		}

		# if we now have the request length and the proper buffer length, read the request
		if (defined $self->{request_length} and length $self->{buffer} >= $self->{request_length}) {
			my $data = substr $self->{buffer}, 0, $self->{request_length};
			$self->{buffer} = substr $self->{buffer}, $self->{request_length};
			# say "got length: $self->{request_length} vs ", length $data;
			# say "got ", unpack 'H*', $data;
			$data = gunzip($data);
			# say "//$data//";
			$data = decode_json($data);
			# say "debug: ", Dumper $data;

			$self->on_request($data);
			$self->{request_length} = undef;
		} else {
			last;
		}
	}

	return
}

sub result {
	my ($self, $res) = @_;
	$res = $res // Carbon::Limestone::Response->new(status => 'server_error', server_error => 'internal server error');
	
	$self->send_response({ %$res });
}

sub send_response {
	my ($self, $res) = @_;

	my $data = gzip(encode_json($res));
	my $data_length = pack 'N', length $data;

	$self->write_to_output_buffer("$data_length$data");
}

sub on_request {
	my ($self, $req) = @_;
	$self->produce_gpc(format_gpc($req));
}

sub format_gpc {
	my ($req) = @_;

	my $uri = Carbon::URI->parse($req->{path});
	$uri->protocol('limestone:');
	return { uri => $uri, data => Carbon::Limestone::Query->new(%{$req->{data}}) }
}

1;
