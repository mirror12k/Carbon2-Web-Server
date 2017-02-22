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

sub read_buffered {
	my ($self) = @_;
	$self->SUPER::read_buffered;

	# say "debug buffer: ", unpack 'H*', $self->{buffer};
	unless (defined $self->{frame}) {
		if (length $self->{buffer} >= 2) {
			my ($flags, $length) = unpack 'CC', substr $self->{buffer}, 0, 2;
			my $mask = $length >> 7;
			$length &= 0x7f;

			my $fin = $flags >> 7;
			my $opcode = $flags & 0xf;
			$flags = ($flags >> 4) & 0x7;

			my $mask_key;

			if ($length == 126 and length $self->{buffer} >= 4 + $mask * 4) {
				$length = unpack 'n', substr $self->{buffer}, 2, 2;
				$self->{buffer} = substr $self->{buffer}, 4;
				if ($mask) {
					$mask_key = substr $self->{buffer}, 0, 4;
					$self->{buffer} = substr $self->{buffer}, 4;
				}
				$self->{frame} = { fin => $fin, opcode => $opcode, flags => $flags, mask => $mask_key, length => $length };
			} elsif ($length == 127 and length $self->{buffer} >= 10 + $mask * 4) {
				$length = unpack 'Q>', substr $self->{buffer}, 2, 8;
				$self->{buffer} = substr $self->{buffer}, 10;
				if ($mask) {
					$mask_key = substr $self->{buffer}, 0, 4;
					$self->{buffer} = substr $self->{buffer}, 4;
				}
				$self->{frame} = { fin => $fin, opcode => $opcode, flags => $flags, mask => $mask_key, length => $length };
			} elsif ($length < 126 and length $self->{buffer} >= 2 + $mask * 4) {
				$self->{buffer} = substr $self->{buffer}, 2;
				if ($mask) {
					$mask_key = substr $self->{buffer}, 0, 4;
					$self->{buffer} = substr $self->{buffer}, 4;
				}
				$self->{frame} = { fin => $fin, opcode => $opcode, flags => $flags, mask => $mask_key, length => $length };
			}
			# say "debug frame: ", Dumper $self->{frame};
			# say "debug buffer: ", unpack 'H*', $self->{buffer};
		}
	}

	# if it has completed the header transfer
	if (defined $self->{frame}) {

		if (length $self->{buffer} >= $self->{frame}{length}) {
			$self->{frame}{data} = substr $self->{buffer}, 0, $self->{frame}{length};
			$self->{buffer} = substr $self->{buffer}, $self->{frame}{length};

			if (defined $self->{frame}{mask}) {
				my $mask_length = length ($self->{frame}{data}) / 4 + 1;
				my $mask = $self->{frame}{mask} x $mask_length;
				$mask = substr $mask, 0, length $self->{frame}{data};
				$self->{frame}{data} ^= $mask;
			}

			$self->on_frame($self->{frame});
			# my $req = $self->{frame}{data};
			$self->{frame} = undef;
		}
	}
	return
}

sub on_frame {
	my ($self, $frame) = @_;
	
	say "debug got frame: ", Dumper $frame;
	my $req = $frame->{data};
	$self->produce_gpc(format_gpc($req, $self->{uri}));
}

sub format_gpc {
	my ($req, $uri) = @_;

	$uri = $uri->clone;
	$uri->protocol('ws:');
	return { uri => $uri, data => $req }
}

1;
