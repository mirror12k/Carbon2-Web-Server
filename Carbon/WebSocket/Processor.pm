package Carbon::WebSocket::Processor;
use parent 'Carbon::Processor';
use strict;
use warnings;

use feature 'say';

use Carbon::WebSocket::ConnectionWrapper;



sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->{paths} = $args{paths};

	return $self
}

sub execute_gpc {
	my ($self, $gpc) = @_;

	my $path = $gpc->{uri}->path;
	my $data = $gpc->{data};

	my $action = $data->{action};
	my $session = $data->{session};

	my $commands = [];

	my $wrapper = Carbon::WebSocket::ConnectionWrapper->new($commands, $session);


	if (exists $self->{paths}{$path}) {
		if (exists $self->{paths}{$path}{$action}) {
			$self->{paths}{$path}{$action}->($wrapper, $data->{data});
		}
	}

	return {
		session => $session,
		commands => $commands, 
		# [
		# 	# { type => 'text', text => "hello there: $text" }
		# ],
	}
}

1;
