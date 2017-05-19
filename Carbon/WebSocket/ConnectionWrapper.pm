package Carbon::WebSocket::ConnectionWrapper;
use strict;
use warnings;

use feature 'say';

sub new {
	my ($class, $commands, $session) = @_;
	my $self = bless {}, $class;

	$self->{commands} = $commands;
	$self->{session} = $session;

	return $self
}

sub session { @_ > 1 ? $_[0]{session} = $_[1] : $_[0]{session} }

sub send {
	my ($self, @text) = @_;
	my $text = join '', @text;
	push @{$self->{commands}}, { type => 'text', text => "$text" };
}

sub close {
	my ($self) = @_;
	push @{$self->{commands}}, { type => 'close' };
}

1;
