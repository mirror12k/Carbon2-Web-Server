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
	$self->processors($args{processors} // {});
	$self->connection_processing_workers($args{connection_processing_workers} // 2);
	$self->request_processing_workers($args{request_processing_workers} // 2);

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

sub processors { @_ > 1 ? $_[0]{carbon_server__processors} = $_[1] : $_[0]{carbon_server__processors} }
sub connection_processing_workers { @_ > 1 ? $_[0]{carbon_server__connection_processing_workers} = $_[1] : $_[0]{carbon_server__connection_processing_workers} }
sub request_processing_workers { @_ > 1 ? $_[0]{carbon_server__request_processing_workers} = $_[1] : $_[0]{carbon_server__request_processing_workers} }






sub warn {
	my ($self, $level, @args) = @_;
	if ($self->{debug} and $self->{debug} <= $level) {
		$self->onwarn->("[". (caller)[0] ."] ", @args, "\n");
	}
}

sub die {
	my ($self, @args) = @_;
	$self->onerror->("[". (caller)[0] ."][$self] ", @args);
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

sub shutdown {
	my ($self) = @_;

	if ($self->server_running) {
		$self->warn(1, "shutdown requested");
		$self->server_running(0);
	} else {
		$self->die("shutdown called twice");
	}
}

sub start_thread_pool {
	my ($self) = @_;

	$self->server_socket_queue(Thread::Queue->new);
	$self->connection_thread_pool(Thread::Pool->new({
		workers => $self->connection_processing_workers,
		pre => sub {
			eval { $self->start_connection_thread($self->server_socket_queue); };
			$self->warn(1, "connection thread died of $@") if $@;
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
			$self->warn(1, "got connection $new_socket");
			$self->server_socket_queue->enqueue(fileno $new_socket);
			push @socket_cache, $new_socket;
		}
	}

}


sub cleanup {
	my ($self) = @_;
	say "cleaning up...";

	$self->server_socket_queue->end;
	$self->connection_thread_pool->shutdown;
}



sub start_connection_thread {
	my ($self, $queue) = @_;

	$self->warn(1, "start_connection_thread");
	$self->processing_thread_pool(Thread::Pool->new({
		workers => $self->request_processing_workers,
		pre => sub {
			eval { $self->init_processing_thread(@_) };
			$self->warn(1, "process thread died during initialization: $@") if $@;
		},
		do => sub {
			my @ret = eval { $self->process_gpc(@_) };
			$self->warn(1, "process thread died: $@") if $@;
			return @ret
		},
	}));

	my $selector = IO::Select->new;
	my %socket_connections;

	$self->server_running(1);

	while ($self->server_running) {
		# $self->warn(1, "debug in server loop");

		if (not defined $queue->pending) {
			$self->server_running(0);
		} elsif ($selector->count) {
			foreach my $socket ($selector->can_read(10 / 1000)) {
				my $connection = $socket_connections{"$socket"};
				$connection->read_buffered;
				while (my $gpc = $connection->produce_gpc) {
					# say "got gpc from connection: ", Dumper $gpc;
					$gpc->{socket} = "$socket";
					# we must read the jobid, otherwise Thread::Pool will think that we don't want the results
					my $jobid = $self->processing_thread_pool->job($gpc);
				}
			}

			my @jobids = $self->processing_thread_pool->results;
			foreach my $jobid ($self->processing_thread_pool->results) {
				my ($socket, @results) = $self->processing_thread_pool->result($jobid);
				# reclaim any socket whose job has completed
				# say "job [$jobid] completed!"; # JOBS DEBUG
				# $self->warn(1, "got result from job $jobid for socket $socket");
				my $connection = $socket_connections{"$socket"};
				# TODO: close connection if results are empty
				$connection->result(@results);
			}

			while (my $socket = $queue->dequeue_nb()) {
				$socket_connections{"$socket"} = Carbon::HTTP::Connection->new($socket);
				$selector->add($socket);
			}
		} else {
			my $socket = $queue->dequeue();
			if (defined $socket) {
				$socket_connections{"$socket"} = Carbon::HTTP::Connection->new($socket);
				$selector->add($socket);
			}
		}
	}

	$self->processing_thread_pool->shutdown;
}

sub init_processing_thread {
	my ($self) = @_;
	my %initialized_processors;
	for my $processor (values %{$self->processors}) {
		$self->warn(1, "initializing processor [" . $processor . "]");
		$processor->init_thread unless exists $initialized_processors{"$processor"};
		$initialized_processors{"$processor"} = 1;
	}
}

sub process_gpc {
	my ($self, $gpc) = @_;
	# say "got gpc in process: ", Dumper $gpc;
	my $uri = $gpc->{uri};

	if (exists $self->processors->{$uri->protocol}) {
		$self->warn(1, "processing gpc '" . $uri->as_string . "' with router [" . $self->processors->{$uri->protocol} . "]");
		return $gpc->{socket}, $self->processors->{$uri->protocol}->execute_gpc($gpc)
	} else {
		$self->warn(1, "no router found for protocol '" . $uri->protocol . "'");
		return
	}
}





1;
