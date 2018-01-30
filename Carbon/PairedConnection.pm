package Carbon::PairedConnection;
use parent 'Carbon::Connection';
use strict;
use warnings;

use feature 'say';



sub new {
	my ($class, $server, $socket, $connection_pair) = @_;
	my $self = $class->SUPER::new($server, $socket);

	$self->{connection_pair} = $connection_pair;
	$self->{is_closing} = 0;
	return $self
}

# callbacks usable by subclasses
sub on_connected {}

sub on_data {}

sub on_disconnected {
	my ($self) = @_;
	# close the pair socket as well as ourselves
	$self->{is_closing} = 1;
	unless ($self->{connection_pair}{is_closing}) {
		$self->{connection_pair}->remove_self;
	}
}

1;
