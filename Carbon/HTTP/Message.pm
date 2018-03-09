package Carbon::HTTP::Message;
use strict;
use warnings;

# a minimalistic implementation of HTTP::Message


sub new {
	my ($class) = @_;
	my $self = bless {}, $class;
	return $self
}


sub message_line; # abstract method for children to override

sub protocol { @_ > 1 ? $_[0]{protocol} = $_[1] : $_[0]{protocol} }
sub content { @_ > 1 ? $_[0]{content} = $_[1] : $_[0]{content} }

# lots of headers methods to be at least slightly compatable with HTTP::Message
sub headers {
	my ($self, $headers) = @_;
	if (@_ == 2) {
		# to offer as much backwards compatability as possible for HTTP::Message, we accept array header lists
		$headers = { @$headers } if ref $headers eq 'ARRAY';

		$self->{headers} = $headers;
	}
	return $self->{headers}
}

sub header {
	my ($self, $key, $val) = @_;
	$key = lc $key;
	if (@_ > 2) {
		if (ref $val eq 'ARRAY') {
			$self->{headers}{$key} = [@$val];
		} else {
			$self->{headers}{$key} = [$val];
		}
	} else {
		return unless exists $self->{headers}{$key};
	}

	# return @{$self->{headers}{$key}} if wantarray;
	return join ", ", @{$self->{headers}{$key}};
}

sub init_header {
	my ($self, $key, $val) = @_;
	$key = lc $key;
	$self->header($key => $val) unless exists $self->{headers}{$key};
}

sub push_header {
	my ($self, $key, $val) = @_;
	$key = lc $key;
	if (ref $val eq 'ARRAY') {
		push @{$self->{headers}{$key}}, @$val;
	} else {
		push @{$self->{headers}{$key}}, $val;
	}
}

sub remove_header {
	my ($self, $key) = @_;
	$key = lc $key;
	delete $self->{headers}{$key};
}


sub parse_headers {
	my ($self, $headers) = @_;

	my %parsed;
	if (defined $headers) {
		for my $kv (map [lc $_->[0] => $_->[1]], map [split /:\s*/, $_, 2], split /\r?\n/, $headers) {
			push @{$parsed{$kv->[0]}}, $kv->[1];
		}
	}

	$self->headers(\%parsed);
}


sub as_string {
	my ($self) = @_;
	my $headers = $self->headers;
	return join "\r\n",
		$self->message_line,
		(map { my $k = $_; map "$k: $_", @{$headers->{$k}} } keys %$headers),
		'',
		$self->content // ''
}


1
