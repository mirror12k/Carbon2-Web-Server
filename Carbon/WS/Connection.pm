package Carbon::WS::Connection;
use parent 'Carbon::Connection';
use strict;
use warnings;

use feature 'say';

use Carbon::URI;

use Data::Dumper;



sub new {
	my ($class, $server, $socket, $uri) = @_;
	my $self = $class->SUPER::new($server, $socket);
	$self->{uri} = $uri;

	return $self
}

sub produce_gpc {
	my ($self) = @_;

	unless (defined $self->{frame}) {
		if (length $self->{buffer} >= 2) {
			my ($flags, $length) = unpack 'CC', substr $self->{buffer}, 2;
			my $mask = $length >> 7;
			$length &= 0x7f;

			my $fin = $flags >> 7;
			my $opcode = $flags & 0xf;
			$flags = ($flags >> 4) & 0x7;


			if ($length == 126 and length $self->{buffer} >= 4) {
				$length = unpack 'n', substr $self->{buffer}, 2, 2;
				$self->{buffer} = substr $self->{buffer}, 4;
				$self->{frame} = { fin => $fin, opcode => $opcode, flags => $flags, mask => $mask, length => $length };
			} elsif ($length == 127 and length $self->{buffer} >= 10) {
				$length = unpack 'Q>', substr $self->{buffer}, 2, 8;
				$self->{buffer} = substr $self->{buffer}, 10;
				$self->{frame} = { fin => $fin, opcode => $opcode, flags => $flags, mask => $mask, length => $length };
			} elsif ($length < 126) {
				$self->{buffer} = substr $self->{buffer}, 2;
				$self->{frame} = { fin => $fin, opcode => $opcode, flags => $flags, mask => $mask, length => $length };
			}
		}
	}

	# if it has completed the header transfer
	if (defined $self->{frame}) {

		if (length $self->{buffer} >= $self->{frame}{length}) {
			$self->{frame}{data} = substr $self->{buffer}, 0, $self->{frame}{length};
			$self->{buffer} = substr $self->{buffer}, $self->{frame}{length};

			my $req = $self->{frame}{data};
			$self->{frame} = undef;
			return format_gpc($req, $self->{uri})
		}
	}
	return
}

sub format_gpc {
	my ($req, $uri) = @_;

	$uri = $uri->clone;
	$uri->protocol('ws:');
	return { uri => $uri, data => $req }
}

1;
