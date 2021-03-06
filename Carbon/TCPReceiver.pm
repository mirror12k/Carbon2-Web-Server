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

	die "failed to open tcp socket on port $self->{port}: $!" unless defined $self->{server_socket};

	return $self->{server_socket}
}

sub restore_socket {
	my ($self, $fd) = @_;
	my $socket = IO::Socket::INET->new;
	$socket->fdopen($fd, 'r+'); # 'rw' stalls
	return $socket
}

# returns a connection object spawned from the given socket
sub start_connection {
	my ($self, $server, $socket) = @_;
	return $self->{connection_class}->new($server, $socket, %{$self->{connection_args}});
}

sub shutdown {
	my ($self) = @_;
	$self->{server_socket}->close;
}

1;
