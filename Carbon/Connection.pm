package Carbon::Connection;
use strict;
use warnings;

use feature 'say';



sub new {
	my ($class, $server, $socket) = @_;
	my $self = bless {}, $class;

	$self->{server} = $server;
	$self->{socket} = $socket;
	$self->{buffer} = '';
	return $self
}

sub read_buffered {
	my ($self) = @_;

	my $read = $self->{socket}->read($self->{buffer}, 4096 * 64, length $self->{buffer});
	my $total = $read // 0;
	while (defined $read and $read > 0) {
		$read = $self->{socket}->read($self->{buffer}, 4096 * 16, length $self->{buffer});
		$total += $read if defined $read;
		# say "error: $!" unless defined $read;
		# say "debug read loop: $read" if defined $read;
	}
	# say "read: $total";
	# $self->delete_socket($fh) if $total == 0;
	$self->remove_self if $total == 0;
}

sub result {
	my ($self) = @_;
	die "unimplemented ->result in $self";
}

sub remove_self {
	my ($self) = @_;
	$self->{server}->remove_connection($self->{socket});
}

sub close {
	my ($self) = @_;
	$self->{socket}->close;
}

sub produce_gpc {
	my ($self, $gpc) = @_;
	$gpc->{socket} = "$self->{socket}";
	$self->{server}->schedule_gpc($gpc)
}

1;
