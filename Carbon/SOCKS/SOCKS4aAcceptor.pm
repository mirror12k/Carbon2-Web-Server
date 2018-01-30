package Carbon::SOCKS::SOCKS4aAcceptor;
use parent 'Carbon::Connection';
use strict;
use warnings;

use feature 'say';

use Carbon::SOCKS::PipedConnection;



sub on_data {
	my ($self) = @_;
	if ($self->{buffer} =~ /\A(.)(.)(.{2})(.{4})([^\0]*\0)/s) {
		my ($socks_version, $command_code, $port, $ip) = ($1, $2, $3, $4);
		$socks_version = ord $socks_version;
		$command_code = ord $command_code;
		$ip = join '.', map ord, split '', $ip;
		$port = unpack 'n', $port;
		
		unless ($socks_version == 4) {
			return $self->remove_self;
		}
		unless ($command_code == 1) {
			return $self->remove_self;
		}

		my $hostport;
		if ($ip eq '0.0.0.1') {
			if ($self->{buffer} =~ /\A(.)(.)(.{2})(.{4})([^\0]*\0)([^\0]*)\0/) {
				$hostport = "$6:$port";
				$self->{buffer} = $';
			} else {
				warn "invalid socks4a message from $self->{peer_address}";
				return $self->remove_self;
			}
		} else {
			$hostport = "$ip:$port";
			$self->{buffer} = $';
		}

		my $proxy_socket = IO::Socket::INET->new(
			Proto => 'tcp',
			PeerAddr => $hostport,
			Blocking => 0,
		);

		my $proxy_connection = Carbon::SOCKS::PipedConnection->new($self->{server}, $proxy_socket, undef);
		my $new_connection = Carbon::SOCKS::PipedConnection->new($self->{server}, $self->{socket}, $proxy_connection);
		$proxy_connection->{connection_pair} = $new_connection;

		$self->{server}->add_connection($proxy_socket, $proxy_connection);
		$self->respawn_as($new_connection);

		$new_connection->write_to_output_buffer("\0\x5a\0\0\0\0\0\0");
		$self->{server}->mark_connection_writable($new_connection);

	}
		# } elsif ($self->{buffer} =~ /\A(.)(.)(.{2})(.{4})([^\0]*\0)/s) {

		# return $mir->disconnect_connection($self) unless $socks_version == 4;
		# return $mir->disconnect_connection($self) unless $command_code == 1;

		# my $hostport;
		# if ($ip eq '0.0.0.1') {
		# 	if ($self->{buffer} =~ /\A(.)(.)(.{2})(.{4})([^\0]*\0)([^\0]*)\0/) {
		# 		$hostport = "$6:$port";
		# 		$self->{buffer} = $';
		# 		$self->{is_socks4a_connection} = 1;
		# 	} else {
		# 		warn "invalid socks4a message from $self->{peer_address}";
		# 		return $mir->disconnect_connection($self);
		# 	}
		# } else {
		# 	$hostport = "$ip:$port";
		# 	$self->{buffer} = $';
		# }
}


1;
