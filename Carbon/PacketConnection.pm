package Carbon::PacketConnection;
use parent 'Carbon::Connection';
use strict;
use warnings;

use feature 'say';

use Data::Dumper;
use Gzip::Faster;
use JSON;

use Carbon::URI;



# generic packet communication connection
# reads 4 byte length header (network order), the reads a json object of that many bytes
# produces gpcs of type "packet:"
# responses are exactly the same, with a 4 byte length header, and a json response object

sub on_data {
	my ($self) = @_;

	while (my $frame = $self->parse_frame) {
		$self->on_request($frame);
	}
}

sub parse_frame {
	my ($self) = @_;

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
		# $data = gunzip($data);
		# # say "//$data//";
		my $frame = decode_json($data);
		# say "debug: ", Dumper $frame;

		$self->{request_length} = undef;
		return $frame
	}

	return
}

sub on_result {
	my ($self, $res) = @_;
	# say "on_result: ", Dumper $res;
	$self->send_response({ %$res });
}

sub send_response {
	my ($self, $res) = @_;

	my $data = encode_json($res);
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
	$uri->protocol('packet:');
	# return { uri => $uri, data => Carbon::Limestone::Query->new(%{$req->{data}}) }
	return { uri => $uri, data => $req->{data} }
}

1;
