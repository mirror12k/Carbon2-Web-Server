package Carbon::WebSocket::TunnelProcessor;
use parent 'Carbon::Processor';
use strict;
use warnings;

use feature 'say';

use JSON;
use Data::Structure::Util 'unbless';

use Data::Dumper;

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{processor} = $args{processor};
	$self->{uri_protocol} = $args{uri_protocol};
	$self->{forbid_path_setting} = $args{forbid_path_setting} // 0;

	return $self
}

sub execute_gpc {
	my ($self, $gpc) = @_;

	my $data = $gpc->{data};
	my $ws_action = $data->{action};
	my $ws_session = $data->{session};

	if ($ws_action eq 'text') {
		my $inner_gpc = decode_json($data->{data});
		# say "debug:", Dumper $inner_gpc;
		
		my $gpc_uri = $gpc->{uri}->clone;
		$gpc_uri->protocol($self->{uri_protocol}) if defined $self->{uri_protocol};
		$gpc_uri->path($inner_gpc->{path}) if not $self->{forbid_path_setting} and exists $inner_gpc->{path};
		$gpc_uri->query($inner_gpc->{query}) if not $self->{forbid_path_setting} and exists $inner_gpc->{query};



		my $response = $self->{processor}->execute_gpc({ uri => $gpc_uri, data => $inner_gpc->{data} });
		# say "debug response:", $response;
		$response = {} unless defined $response;
		return { session => $ws_session, commands => [
			{
				type => 'text',
				text => encode_json(unbless($response)),
			}
		] };
	} else {
		return { session => $ws_session, commands => [] };
	}
}

1;
