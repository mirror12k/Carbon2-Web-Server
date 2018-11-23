package Carbon::SSLReceiver;
use parent 'Carbon::TCPReceiver';
use strict;
use warnings;

use feature 'say';

use Carp;

use IO::Socket::INET;
use IO::Socket::SSL;



sub new {
	my ($class, $port, $connection_class, %args) = @_;
	my $self = $class->SUPER::new($port, $connection_class, %args);

	$self->{ssl_certificate} = $args{ssl_certificate} // confess 'ssl_certificate argument required';
	$self->{ssl_key} = $args{ssl_key} // confess 'ssl_key argument required';

	return $self
}

sub restore_socket {
	my ($self, $fd) = @_;
	my $socket = IO::Socket::INET->new;
	$socket->fdopen($fd, 'r+'); # 'rw' stalls
	$socket = IO::Socket::SSL->start_SSL($socket,
		SSL_server => 1,
		SSL_cert_file => $self->{ssl_certificate},
		SSL_key_file => $self->{ssl_key},
		Blocking => 0,
	) or warn "failed to ssl handshake insock: $SSL_ERROR";
	return $socket
}

1;
