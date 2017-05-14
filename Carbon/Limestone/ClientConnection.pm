package Carbon::Limestone::ClientConnection;
use strict;
use warnings;

use feature 'say';

use Carp;
use Data::Dumper;
use Gzip::Faster;
use JSON;

use IO::Socket::INET;
use IO::Socket::SSL;

use Carbon::URI;
use Carbon::Limestone::Query;
use Carbon::Limestone::Response;



sub new {
	my ($class, %args) = @_;
	my $self = bless {}, $class;

	my $uri = Carbon::URI->parse($args{uri});
	if ($uri->protocol eq 'limestone:' or $uri->protocol eq 'limestonessl:') {
		$self->{protocol} = $uri->{protocol};
	} else {
		croak "invalid uri protocol: " . $uri->protocol;
	}

	$self->{hostport} = $uri->host . ":" . ($uri->port // '2047');

	return $self
}

sub connect {
	my ($self) = @_;
	$self->{socket} = IO::Socket::INET->new(
		PeerAddr => $self->{hostport},
		Proto => 'tcp',
	);
	warn "failed to connect: $!" unless $self->{socket};

	return $self->{socket}
}

sub send_request {
	my ($self, $req) = @_;
	
	# say "debug: ", Dumper $req;
	my $data = encode_json $req;
	# say "//$data//";
	$data = gzip($data);
	my $data_length = pack 'N', length $data;

	# say "sending ", length $data;
	# say "sending ", unpack 'H*', $data;
	$self->{socket}->print("$data_length$data");
}

sub recieve_response {
	my ($self) = @_;

	my $data;
	$self->{socket}->read($data, 4);
	return unless $data and length $data == 4;

	my $data_length = unpack 'N', $data;
	$self->{socket}->read($data, $data_length);
	return unless $data and length $data == $data_length;

	$data = decode_json(gunzip($data));

	return $data
}

sub query {
	my ($self, $path, $query) = @_;

	$self->send_request({ path => $path, data => { %$query } });
	return $self->recieve_response
}

1;
