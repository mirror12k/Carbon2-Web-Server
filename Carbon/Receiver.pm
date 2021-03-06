package Carbon::Receiver;
use strict;
use warnings;

use feature 'say';

use Carp;



sub new {
	my ($class, $port, $connection_class, %args) = @_;
	my $self = bless {}, $class;

	$self->{port} = $port // croak "port required";
	$self->{connection_class} = $connection_class // croak "connection class required";
	
	$self->{connection_args} = $args{connection_args} // {};

	return $self
}

# returns any connection-accepting sockets that need to be created
sub start_sockets {
	my ($self) = @_;
	die "unimplemented ->start_sockets in $self";
}

# restore a socket from file descriptor after it has been passed through a thread conveyer
sub restore_socket {
	my ($self, $fd) = @_;
	die "unimplemented ->restore_socket in $self";
}

# returns a connection object spawned from the given socket
sub start_connection {
	my ($self, $socket) = @_;
	die "unimplemented ->start_connection in $self";
}

# orders the complete shutdown of any listening sockets
sub shutdown {
	my ($self) = @_;
	die "unimplemented ->shutdown in $self";
}

1;
