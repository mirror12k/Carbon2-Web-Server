package Carbon::WebSocket::HTTPPromoter;
use parent 'Carbon::HTTP::Connection';
use strict;
use warnings;

use feature 'say';

use MIME::Base64;
use Digest::SHA 'sha1';

use Carbon::URI;
use Carbon::HTTP::Response;
use Carbon::WebSocket::Connection;

use Data::Dumper;



sub on_http_request {
	my ($self, $req) = @_;

	return $self->remove_with_error('bad method')
			unless $req->method eq 'GET';
	return $self->remove_with_error('bad connection header')
			unless defined $req->header('connection') and $req->header('connection') =~ /\bupgrade\b/i;
	return $self->remove_with_error('bad upgrade')
			unless defined $req->header('upgrade') and lc $req->header('upgrade') eq 'websocket';
	return $self->remove_with_error('bad websocket version')
			unless defined $req->header('Sec-WebSocket-Version') and $req->header('Sec-WebSocket-Version') eq '13';
	return $self->remove_with_error('missing Sec-WebSocket-Key header')
			unless defined $req->header('Sec-WebSocket-Key');


	my $key = sha1($req->header('Sec-WebSocket-Key') . '258EAFA5-E914-47DA-95CA-C5AB0DC85B11');
	$key = encode_base64($key, '');

	my $res = Carbon::HTTP::Response->new('101', 'Switching Protocols');
	$res->header(Connection => 'Upgrade');
	$res->header(Upgrade => 'websocket');
	$res->header('Sec-WebSocket-Accept' => $key);
	$self->{socket}->print($res->as_string);

	$self->respawn_as(Carbon::WebSocket::Connection->new($self->{server}, $self->{socket}, $req->{uri}));
}

sub remove_with_error {
	my ($self, $reason) = @_;
	warn "closing websocket handshake because of: $reason";
	$self->remove_self;
}

1;
