package Carbon2;

use strict;
use warnings;

use feature 'say';

use Carp;

use IO::Socket::INET;
use IO::Select;
use Thread::Pool;
use Thread::Queue;
use Time::HiRes 'usleep';

use Carbon::URI;

=pod

incoming connection requests will be 

GPCs will be organized as { uri => 'some://uri', data => <something>, connection_data => {} }
they will be queued into a thread::pool for execution where another thread will execute the request with first available handler
return will be a... string?

=cut

sub new ($%) {
	my ($class, %args) = @_;
	my $self = bless {}, $class;

	$self->debug($args{debug} // 0);

	$self->onwarn($args{onwarn} // \&CORE::warn);
	$self->onerror($args{onerror} // \&Carp::confess);
	
	$self->port($args{port} // 2048);
	$self->routers($args{routers} // {});

	$self->server_running(0);

	return $self
}



sub debug { @_ > 1 ? $_[0]{debug} = $_[1] : $_[0]{debug} }
sub onwarn { @_ > 1 ? $_[0]{carbon_server__onwarn} = $_[1] : $_[0]{carbon_server__onwarn} }
sub onerror { @_ > 1 ? $_[0]{carbon_server__onerror} = $_[1] : $_[0]{carbon_server__onerror} }

sub server_running { @_ > 1 ? $_[0]{carbon_server__running} = $_[1] : $_[0]{carbon_server__running} }

sub port { @_ > 1 ? $_[0]{carbon_server__port} = $_[1] : $_[0]{carbon_server__port} }
# sub server_socket { @_ > 1 ? $_[0]{carbon_server__server_socket} = $_[1] : $_[0]{carbon_server__server_socket} }
# sub socket_selector { @_ > 1 ? $_[0]{carbon_server__socket_selector} = $_[1] : $_[0]{carbon_server__socket_selector} }
sub connection_thread_pool { @_ > 1 ? $_[0]{carbon_server__connection_thread_pool} = $_[1] : $_[0]{carbon_server__connection_thread_pool} }
sub processing_thread_pool { @_ > 1 ? $_[0]{carbon_server__processing_thread_pool} = $_[1] : $_[0]{carbon_server__processing_thread_pool} }

sub routers { @_ > 1 ? $_[0]{carbon_server__routers} = $_[1] : $_[0]{carbon_server__routers} }






sub warn {
	my ($self, $level, @args) = @_;
	if ($self->{debug} and $self->{debug} <= $level) {
		$self->onwarn->("[$self][". (caller)[0] ."] ", @args, "\n");
	}
}

sub die {
	my ($self, @args) = @_;
	$self->onerror->("[$self] ", @args);
	CORE::die "returning from onerror is not allowed";
}


sub start {
	my ($self) = @_;

	$self->start_thread_pool;
	# $self->start_server_socket;

	$self->warn(1, "started carbon server on port ". $self->port);
	$self->server_running(1);
	$self->listen_accept_server_loop;

	$self->cleanup;
}

sub start_thread_pool {
	my ($self) = @_;

	$self->connection_thread_pool(Thread::Pool->new({
		workers => 10,
		pre => sub { $self->start_connection_thread(@_) },
		do => sub { say 'lol nope' },
	}));
}

sub listen_accept_server_loop {
	my ($self) = @_;

	# my $server_socket = 

	# while the server is running
	while ($self->server_running) {
		say "in loop";
		sleep 1;
		$self->server_running(0);
		# # update the thread_pool to receive any completed jobs
		# $self->update_thread_pool;
		# # update the server socket to receive any new connections
		# $self->accept_new_connections;
		# # update sockets to receive any new messages and dispatch any jobs necessary
		# # this method needs to perform some delay operation to prevent 100% cpu usage
		# $self->update_sockets;
	}

}


sub cleanup {
	my ($self) = @_;
	say "cleaning up...";

	$self->connection_thread_pool->join;
}



sub start_connection_thread {
	my ($self, $queue) = @_;

	$self->processing_thread_pool(Thread::Pool->new({
		workers => 10,
		pre => sub { $self->init_processing_thread(@_) },
		do => sub { return $self->process_gpc(@_) },
	}));

	$self->processing_thread_pool->job({ uri => 'http://lol' });
	$self->processing_thread_pool->job({ uri => 'nope://lol' });

	$self->processing_thread_pool->join;
}

sub init_processing_thread {
	my ($self) = @_;
	for my $router (keys %{$self->routers}) {
		# $self->warn(1, "initializing router [" . $router . "] in processing thread");
	}
}

sub process_gpc {
	my ($self, $gpc) = @_;
	my $uri = Carbon::URI->parse($gpc->{uri});

	if (exists $self->routers->{$uri->protocol}) {
		$self->warn(1, "processing protocol '" . $uri->protocol . "' with router [" . $self->routers->{$uri->protocol} . "]");
		# say "processing with router: ", $self->routers->{$uri->protocol};
		return 1
	} else {
		$self->warn(1, "no router found for protocol '" . $uri->protocol . "'");
		return 0
	}
}





1;
