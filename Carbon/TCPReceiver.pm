package Carbon::TCPReceiver;
use parent 'Carbon::Receiver';
use strict;
use warnings;

use feature 'say';

use IO::Socket::INET;



sub start_sockets {
	my ($self) = @_;
	# the primary server socket which will be receiving connections
	$self->{server_socket} = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalPort => $self->{port},
		Listen => SOMAXCONN,
		Reuse => 1,
		Blocking => 0,
	);
	return $self->{server_socket}
}

# returns a connection object spawned from the given socket
sub start_connection {
	my ($self, $socket) = @_;
	return $self->{connection_class}->new($socket)
}

sub shutdown {
	my ($self) = @_;
	$self->{server_socket}->close;
}

1;
