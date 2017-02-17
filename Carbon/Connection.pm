package Carbon::Connection;
use strict;
use warnings;

use feature 'say';



sub new {
	my ($class, $socket) = @_;
	my $self = bless {}, $class;

	$self->{socket} = $socket;
	$self->{buffer} = '';
	return $self
}

sub read_buffered {
	my ($self) = @_;

	$self->{socket}->read($self->{buffer}, 4096 * 64, length $self->{buffer});
	my $read = 1;
	my $total = 0;
	while (defined $read and $read > 0) {
		$read = $self->{socket}->read($self->{buffer}, 4096 * 16, length $self->{buffer});
		$total += $read if defined $read;
		# say "debug read loop: $read";
	}
	# $self->delete_socket($fh) if $total == 0;
}

sub produce_gpc {
	my ($self) = @_;
	die "unimplemented ->produce_gpc in $self";
}

sub result {
	my ($self) = @_;
	die "unimplemented ->result in $self";
}

sub close {
	my ($self) = @_;
	$self->{socket}->close;
}

1;
