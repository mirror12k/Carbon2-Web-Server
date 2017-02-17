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
use Carbon::HTTP::Connection;

use Data::Dumper;

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
	$self->connection_processing_workers($args{connection_processing_workers} // 10);
	$self->request_processing_workers($args{request_processing_workers} // 10);

	$self->server_running(0);

	return $self
}



sub debug { @_ > 1 ? $_[0]{debug} = $_[1] : $_[0]{debug} }
sub onwarn { @_ > 1 ? $_[0]{carbon_server__onwarn} = $_[1] : $_[0]{carbon_server__onwarn} }
sub onerror { @_ > 1 ? $_[0]{carbon_server__onerror} = $_[1] : $_[0]{carbon_server__onerror} }

sub server_running { @_ > 1 ? $_[0]{carbon_server__running} = $_[1] : $_[0]{carbon_server__running} }

sub port { @_ > 1 ? $_[0]{carbon_server__port} = $_[1] : $_[0]{carbon_server__port} }
sub server_socket { @_ > 1 ? $_[0]{carbon_server__server_socket} = $_[1] : $_[0]{carbon_server__server_socket} }
sub socket_selector { @_ > 1 ? $_[0]{carbon_server__socket_selector} = $_[1] : $_[0]{carbon_server__socket_selector} }
sub server_socket_queue { @_ > 1 ? $_[0]{carbon_server__server_socket_queue} = $_[1] : $_[0]{carbon_server__server_socket_queue} }
sub connection_thread_pool { @_ > 1 ? $_[0]{carbon_server__connection_thread_pool} = $_[1] : $_[0]{carbon_server__connection_thread_pool} }
sub processing_thread_pool { @_ > 1 ? $_[0]{carbon_server__processing_thread_pool} = $_[1] : $_[0]{carbon_server__processing_thread_pool} }

sub routers { @_ > 1 ? $_[0]{carbon_server__routers} = $_[1] : $_[0]{carbon_server__routers} }
sub connection_processing_workers { @_ > 1 ? $_[0]{carbon_server__connection_processing_workers} = $_[1] : $_[0]{carbon_server__connection_processing_workers} }
sub request_processing_workers { @_ > 1 ? $_[0]{carbon_server__request_processing_workers} = $_[1] : $_[0]{carbon_server__request_processing_workers} }






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
	$self->start_server_socket;

	$self->warn(1, "started carbon server on port ". $self->port);
	$self->server_running(1);
	$self->listen_accept_server_loop;

	$self->cleanup;
}

sub start_thread_pool {
	my ($self) = @_;

	$self->server_socket_queue(Thread::Queue->new);
	$self->connection_thread_pool(Thread::Pool->new({
		workers => $self->connection_processing_workers,
		pre => sub {
			eval { $self->start_connection_thread($self->server_socket_queue); };
			$self->warn("connection thread died of $@") if $@;
		},
		do => sub { say 'lol nope' },
	}));
}

sub start_server_socket {
	my ($self) = @_;

	# the primary server socket which will be receiving connections
	my $sock = IO::Socket::INET->new(
		Proto => 'tcp',
		LocalPort => $self->port,
		Listen => SOMAXCONN,
		Reuse => 1,
		Blocking => 0,
	) or $self->die("failed to start socket: $!");
	$self->server_socket($sock);

	$self->socket_selector(IO::Select->new);
	$self->socket_selector->add($self->server_socket);
}

sub listen_accept_server_loop {
	my ($self) = @_;

	my @socket_cache;
	# while the server is running
	while ($self->server_running) {
		# say "in loop";
		foreach my $socket ($self->socket_selector->can_read(500 / 1000)) {
			my $new_socket = $socket->accept;
			$new_socket->blocking(0); # set it to non-blocking
			$self->warn(1, "debug got connection $new_socket");
			$self->server_socket_queue->enqueue(fileno $new_socket);
			push @socket_cache, $new_socket;
		}
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

	$self->connection_thread_pool->shutdown;
}



sub start_connection_thread {
	my ($self, $queue) = @_;

	$self->warn(1, "debug start_connection_thread");
	$self->processing_thread_pool(Thread::Pool->new({
		workers => $self->request_processing_workers,
		pre => sub { $self->init_processing_thread(@_) },
		do => sub {
			eval { return $self->process_gpc(@_) };
			$self->warn("process thread died of $@") if $@;
		},
	}));

	my $selector = IO::Select->new;
	my %socket_connections;

	$self->server_running(1);

	while ($self->server_running) {
		# $self->warn(1, "debug in server loop");
		usleep (50 * 1000) unless $selector->count;

		foreach my $socket ($selector->can_read(50 / 1000)) {
			my $connection = $socket_connections{"$socket"};
			$connection->read_buffered;
			while (my $gpc = $connection->produce_gpc) {
				# say "got gpc from connection: ", Dumper $gpc;
				$self->processing_thread_pool->job($gpc);
			}
		}

		while (my $socket = $queue->dequeue_nb()) {
			$socket_connections{"$socket"} = Carbon::HTTP::Connection->new($socket);
			$selector->add($socket);
		}
	}

	$self->processing_thread_pool->shutdown;
}

sub init_processing_thread {
	my ($self) = @_;
	for my $router (keys %{$self->routers}) {
		# $self->warn(1, "initializing router [" . $router . "] in processing thread");
	}
}

sub process_gpc {
	my ($self, $gpc) = @_;
	# say "got gpc in process: ", Dumper $gpc;
	my $uri = $gpc->{uri};

	if (exists $self->routers->{$uri->protocol}) {
		$self->warn(1, "processing gpc '" . $uri->as_string . "' with router [" . $self->routers->{$uri->protocol} . "]");
		# say "processing with router: ", $self->routers->{$uri->protocol};
		return 1
	} else {
		$self->warn(1, "no router found for protocol '" . $uri->protocol . "'");
		return 0
	}
}





1;
