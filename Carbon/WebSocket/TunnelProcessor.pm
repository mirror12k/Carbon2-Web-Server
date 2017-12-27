package Carbon::WebSocket::TunnelProcessor;
use parent 'Carbon::Processor';
use strict;
use warnings;

use feature 'say';

use JSON;

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{processor} = $args{processor};

	return $self
}

sub execute_gpc {
	my ($self, $gpc) = @_;

	my $data = $gpc->{data};
	my $ws_action = $data->{action};
	my $ws_session = $data->{session};

	if ($ws_action eq 'text') {
		my $gpc_uri = $gpc->{uri};
		my $gpc_data = decode_json($data->{data});

		my $response = $self->{processor}->execute_gpc({ uri => $gpc_uri, data => $gpc_data });
		return { session => $ws_session, commands => [
			type => 'text',
			text => encode_json($response),
		] };
	} else {
		return { session => $ws_session, commands => [] };
	}
}

1;
