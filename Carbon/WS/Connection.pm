package Carbon::WS::Connection;
use parent 'Carbon::Connection';
use strict;
use warnings;

use feature 'say';

use Carbon::URI;

use Carp;
use Data::Dumper;



sub new {
	my ($class, $server, $socket, $uri) = @_;
	my $self = $class->SUPER::new($server, $socket);
	$self->{uri} = $uri;

	return $self
}

our %frame_opcode_types = (
	0x0 => 'continuation',
	0x1 => 'text',
	0x2 => 'binary',
	0x3 => 'reserved',
	0x4 => 'reserved',
	0x5 => 'reserved',
	0x6 => 'reserved',
	0x7 => 'reserved',
	0x8 => 'close',
	0x9 => 'ping',
	0xA => 'pong',
	0xB => 'reserved',
	0xC => 'reserved',
	0xD => 'reserved',
	0xE => 'reserved',
	0xF => 'reserved',
);

sub read_buffered {
	my ($self) = @_;
	$self->SUPER::read_buffered;

	my $frame_found;

	do {
		$frame_found = 0;
		# say "debug buffer: ", unpack 'H*', $self->{buffer};
		unless (defined $self->{frame}) {
			if (length $self->{buffer} >= 2) {
				my ($flags, $length) = unpack 'CC', substr $self->{buffer}, 0, 2;
				my $mask = $length >> 7;
				$length &= 0x7f;

				my $fin = $flags >> 7;
				my $opcode = $flags & 0xf;
				$opcode = $frame_opcode_types{$opcode};
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
				$frame_found = 1;
			}
		}
	} while ($frame_found);
}

sub on_frame {
	my ($self, $frame) = @_;

	say "debug got frame: ", Dumper $frame;
	if ($frame->{opcode} eq 'continuation') {
		if (defined $self->{fragmented_frame}) {
			$self->{fragmented_frame}{data} .= $frame->{data};
			if ($frame->{fin}) {
				$self->on_text_frame($self->{fragmented_frame});
				$self->{fragmented_frame} = undef;
			}
		} else {
			warn "invalid continuation frame from client";
			$self->remove_self;
		}
	} elsif ($frame->{opcode} eq 'text' or $frame->{opcode} eq 'binary') {
		if ($frame->{fin}) {
			$self->on_text_frame($frame);
		} else {
			$self->{fragmented_frame} = $frame;
		}
	} elsif ($frame->{opcode} eq 'close') {
		$self->remove_self;
	} elsif ($frame->{opcode} eq 'ping') {
		# nothing
	} elsif ($frame->{opcode} eq 'pong') {
		# nothing
	} elsif ($frame->{opcode} eq 'reserved') {
		warn "invalid frame from client";
		$self->remove_self;
	} else {
		confess "critical error";
	}

}

sub on_text_frame {
	my ($self, $frame) = @_;
	say "got text frame: $frame->{data}";
	$self->send_frame({
		fin => 1,
		flags => 0,
		opcode => 1,
		data => 'hi there!',
	});
	$self->produce_gpc(format_gpc($frame->{data}, $self->{uri}));
}

sub send_frame {
	my ($self, $frame) = @_;

	$frame->{length} = length $frame->{data};
	$frame->{mask_bit} = $frame->{mask} ? 1 : 0;
	
	my $flags_byte = ($frame->{fin} << 7) | ($frame->{flags} << 4) | ($frame->{opcode});
	my $length_byte = ($frame->{mask_bit} << 7);
	if ($frame->{length} >= 65536) {
		$length_byte |= 127;
	} elsif ($frame->{length} >= 126) {
		$length_byte |= 126;
	} else {
		$length_byte |= $frame->{length};
	}

	my $data = pack 'CC', $flags_byte, $length_byte;
	if ($frame->{length} >= 65536) {
		$data .= pack 'Q>', $frame->{length};
	} elsif ($frame->{length} >= 126) {
		$data .= pack 'n', $frame->{length};
	}

	if ($frame->{mask}) {
		$data .= $frame->{mask};
		my $mask_length = length ($frame->{data}) / 4 + 1;
		my $mask = $frame->{mask} x $mask_length;
		$mask = substr $mask, 0, length $frame->{data};
		$frame->{data} ^= $mask;
	}

	$data .= $frame->{data};

	$self->{socket}->print($data);
}

sub format_gpc {
	my ($req, $uri) = @_;

	$uri = $uri->clone;
	$uri->protocol('ws:');
	return { uri => $uri, data => $req }
}

sub result {
	my ($self) = @_;
	# nothing
}

1;
