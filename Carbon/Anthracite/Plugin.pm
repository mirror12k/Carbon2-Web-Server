package Carbon::Anthracite::Plugin;
use strict;
use warnings;

use feature 'say';

# a base plugin class to provide stub methods

sub new {
	my ($class) = @_;
	my $self = bless {}, $class;

	return $self
}


# called when the compiler is created
# this allows the plugin a reference to its compiler and time to do anything fancy
sub initialize {
	my ($self, $compiler) = @_;
}

# called when a worker thread is started
# allows the plugin to start per-thread resources
sub init_thread {
	my ($self) = @_;
}


# called when a token is parsed from a file to be compiled
# returns a string of code to be appended and a reference to a new token
# the token can be the same, can be edited, or can be undef to stop propagating the token
sub compile_token {
	my ($self, $token) = @_;
	return '', $token
}

# called when the code header is being compiled
# returns a string of code to be appended after the compiler's code header
sub code_header {
	my ($self, $data) = @_;
	return ''
}


# called when the code tail is being compiled
# returns a string of code to be appended before the compiler's code tail
sub code_tail {
	my ($self, $data) = @_;
	return ''
}

# called when a runtime is being created
# returns a runtime reference (can be replaced or edited or just left alone)
sub create_runtime {
	my ($self, $runtime) = @_;
	return $runtime
}

1;

