package Carbon::SOCKS::PipedConnection;
use parent 'Carbon::PairedConnection';
use strict;
use warnings;

use feature 'say';



sub on_data {
	my ($self) = @_;

	$self->{connection_pair}->write_to_output_buffer($self->{buffer});
	$self->{server}->mark_connection_writable($self->{connection_pair});
	$self->{buffer} = '';
}

1;
