package Carbon2;

use strict;
use warnings;

use feature 'say';

use Carp;

use IO::Select;
use Thread::Pool;
use Thread::Queue;
use Time::HiRes qw/ usleep /;

use Carbon::URI;
use Carbon::AsyncProcessor;

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
	
	$self->receivers($args{receivers} // []);
	$self->processors($args{processors} // {});
	$self->connection_processing_workers($args{connection_processing_workers} // 2);
	$self->request_processing_workers($args{request_processing_workers} // 2);

	$self->receiver_map({});
	$self->server_running(0);

	return $self
}



sub debug { @_ > 1 ? $_[0]{debug} = $_[1] : $_[0]{debug} }
sub onwarn { @_ > 1 ? $_[0]{carbon_server__onwarn} = $_[1] : $_[0]{carbon_server__onwarn} }
sub onerror { @_ > 1 ? $_[0]{carbon_server__onerror} = $_[1] : $_[0]{carbon_server__onerror} }

sub server_running { @_ > 1 ? $_[0]{carbon_server__running} = $_[1] : $_[0]{carbon_server__running} }

sub socket_selector { @_ > 1 ? $_[0]{carbon_server__socket_selector} = $_[1] : $_[0]{carbon_server__socket_selector} }
sub server_socket_queue { @_ > 1 ? $_[0]{carbon_server__server_socket_queue} = $_[1] : $_[0]{carbon_server__server_socket_queue} }
sub connection_thread_pool { @_ > 1 ? $_[0]{carbon_server__connection_thread_pool} = $_[1] : $_[0]{carbon_server__connection_thread_pool} }
sub processing_thread_pool { @_ > 1 ? $_[0]{carbon_server__processing_thread_pool} = $_[1] : $_[0]{carbon_server__processing_thread_pool} }
sub scheduled_jobs { @_ > 1 ? $_[0]{carbon_server__scheduled_jobs} = $_[1] : $_[0]{carbon_server__scheduled_jobs} }

sub receivers { @_ > 1 ? $_[0]{carbon_server__receivers} = $_[1] : $_[0]{carbon_server__receivers} }
sub receiver_map { @_ > 1 ? $_[0]{carbon_server__receiver_map} = $_[1] : $_[0]{carbon_server__receiver_map} }
sub processors { @_ > 1 ? $_[0]{carbon_server__processors} = $_[1] : $_[0]{carbon_server__processors} }
sub connection_processing_workers { @_ > 1 ? $_[0]{carbon_server__connection_processing_workers} = $_[1] : $_[0]{carbon_server__connection_processing_workers} }
sub request_processing_workers { @_ > 1 ? $_[0]{carbon_server__request_processing_workers} = $_[1] : $_[0]{carbon_server__request_processing_workers} }

sub processing_selector { @_ > 1 ? $_[0]{carbon_server__processing_selector} = $_[1] : $_[0]{carbon_server__processing_selector} }
sub async_processor { @_ > 1 ? $_[0]{carbon_server__async_processor} = $_[1] : $_[0]{carbon_server__async_processor} }
sub async_command_queue { @_ > 1 ? $_[0]{carbon_server__async_command_queue} = $_[1] : $_[0]{carbon_server__async_command_queue} }
sub active_connections { @_ > 1 ? $_[0]{carbon_server__active_connections} = $_[1] : $_[0]{carbon_server__active_connections} }





sub warn {
	my ($self, $level, @args) = @_;
	if ($self->{debug} and $self->{debug} <= $level) {
		$self->onwarn->("[". (caller)[0] ."][" . (Thread::Pool->self // 'main') . "] ", @args, "\n");
	}
}

sub die {
	my ($self, @args) = @_;
	$self->onerror->("[". (caller)[0] ."][$self][" . (Thread::Pool->self // 'main') . "] ", @args, "\n");
	CORE::die "returning from onerror is not allowed";
}


sub start {
	my ($self) = @_;

	$self->start_server_sockets;
	$self->start_thread_pool;

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

	$self->processing_thread_pool(Thread::Pool->new({
		workers => $self->request_processing_workers,
		pre => sub {
			eval { $self->init_processing_thread(@_) };
			$self->warn(1, "processing thread died during initialization: $@") if $@;
		},
		do => sub {
			my @ret = eval { $self->process_gpc(@_) };
			$self->warn(1, "processing thread died: $@") if $@;
			return @ret
		},
	}));

	$self->connection_thread_pool(Thread::Pool->new({
		workers => $self->connection_processing_workers,
		pre => sub {
			eval { $self->start_connection_thread($self->server_socket_queue); };
			$self->warn(1, "connection thread died of $@") if $@;
		},
		do => sub { say 'lol nope' },
	}));
}

sub start_server_sockets {
	my ($self) = @_;

	$self->socket_selector(IO::Select->new);

	for my $receiver (@{$self->receivers}) {
		my @sockets = $receiver->start_sockets;
		for my $socket (@sockets) {
			$self->socket_selector->add($socket);
			$self->receiver_map->{"$socket"} = $receiver;
		}
	}
}

sub listen_accept_server_loop {
	my ($self) = @_;

	my @socket_cache;
	# while the server is running
	while ($self->server_running) {
		# say "in loop";
		foreach my $socket ($self->socket_selector->can_read(500 / 1000)) {
			my $new_socket = $socket->accept;
			# $self->warn(1, "got connection $new_socket");
			$new_socket->blocking(0); # set it to non-blocking
			$self->server_socket_queue->enqueue([ "$socket", fileno $new_socket ]);
			push @socket_cache, $new_socket;
		}
	}

}


sub cleanup {
	my ($self) = @_;
	$self->warn(1, "cleaning up...");

	for my $receiver (@{$self->receivers}) {
		$receiver->shutdown;
	}

	$self->server_socket_queue->end;
	$self->warn(1, "shutting down connection thread pool");
	$self->connection_thread_pool->shutdown;
	$self->warn(1, "shutting down processing thread pool");
	$self->processing_thread_pool->shutdown;
}



sub start_connection_thread {
	my ($self, $queue) = @_;

	$self->warn(1, "starting connection thread");

	$self->processing_selector(IO::Select->new);
	$self->active_connections({});
	$self->scheduled_jobs({});
	$self->async_processor(Carbon::AsyncProcessor->new(delay => 50));



	$self->async_processor->schedule_job(sub {
			# $self->warn(1, "checking socket queue"); # DEBUG PROCESSOR LOOP
			if (not defined $queue->pending) {
				$self->async_processor->running(0);
			} elsif ($self->processing_selector->count == 0) {
				my $instruction = $queue->dequeue();
				if (defined $instruction) {
					my ($parent_socket, $socket) = @$instruction;
					my $receiver = $self->receiver_map->{$parent_socket};

					$socket = $receiver->restore_socket($socket);
					my $connection = $receiver->start_connection($self, $socket);

					$self->add_connection($socket, $connection);
					# $self->active_connections->{"$socket"} = $connection;
					# $self->processing_selector->add($socket);

					# $self->async_processor->schedule_delayed_job(sub {
					# 	say "timeout for connection $connection";
					# 	$connection->remove_self;
					# }, 0.5)
				}
			} else {
				while (my $instruction = $queue->dequeue_nb()) {
					my ($parent_socket, $socket) = @$instruction;
					my $receiver = $self->receiver_map->{$parent_socket};

					$socket = $receiver->restore_socket($socket);
					my $connection = $receiver->start_connection($self, $socket);

					$self->add_connection($socket, $connection);
					# $self->active_connections->{"$socket"} = $connection;
					# $self->processing_selector->add($socket);
				}
			}
		}, 1);

	$self->async_processor->schedule_job(sub {
			# $self->warn(1, "reading from awaiting sockets"); # DEBUG PROCESSOR LOOP
			foreach my $socket ($self->processing_selector->can_read(0)) {
				my $connection = $self->active_connections->{"$socket"};
				$connection->read_buffered;
			}
		}, 1);

	$self->async_processor->schedule_job(sub {
			# $self->warn(1, "checking processing results"); # DEBUG PROCESSOR LOOP
			if (keys %{$self->scheduled_jobs} > 0) {
				my @jobids = $self->processing_thread_pool->results;
				foreach my $jobid ($self->processing_thread_pool->results) {
					if (exists $self->scheduled_jobs->{$jobid}) {
						delete $self->scheduled_jobs->{$jobid};
						# $self->warn(1, ": got result from job $jobid"); # DEBUG JOBS
						my ($socket, $async_commands, @results) = $self->processing_thread_pool->result($jobid);

						# queue up any scheduled async jobs that the gpc produced
						foreach my $command (@$async_commands) {
							my ($callback, $delay, @args) = @$command;
							# $self->warn(1, "got async command: @$command");
							# we need to restore the callback since passing around code refs is not allowed
							$callback = \&{$callback};
							$self->schedule_async_job($callback, $delay, @args);
						}

						# reclaim any socket whose job has completed
						my $connection = $self->active_connections->{"$socket"};
						# TODO: close connection if results are empty
						$connection->result(@results);
					}
				}
			}
		}, 1);

	$self->async_processor->schedule_job(sub {
			# $self->warn(1, "writing to awaiting sockets"); # DEBUG PROCESSOR LOOP
			foreach my $socket ($self->processing_selector->can_write(0)) {
				my $connection = $self->active_connections->{"$socket"};
				$connection->write_buffered;
			}
		}, 1);

	$self->async_processor->process_loop;
}

sub recast_connection {
	my ($self, $connection_socket, $new_connection) = @_;

	$self->warn(1, "recast socket $connection_socket as $new_connection");
	$self->active_connections->{"$connection_socket"} = $new_connection;
}

sub add_connection {
	my ($self, $connection_socket, $connection) = @_;

	$self->warn(1, "new socket $connection_socket");
	$self->processing_selector->add($connection_socket);
	$self->active_connections->{"$connection_socket"} = $connection;
}

sub remove_connection {
	my ($self, $connection_socket) = @_;

	$self->warn(1, "closing socket $connection_socket");
	$self->processing_selector->remove($connection_socket);
	$self->active_connections->{"$connection_socket"}->close;
	delete $self->active_connections->{"$connection_socket"};
}

sub schedule_async_job {
	my ($self, $job, $delay, @args) = @_;

	# in connection thread context, we just put it directly into the async_processor
	if (defined $self->async_processor) {
		if (defined $delay) {
			$self->async_processor->schedule_delayed_job($job, $delay, @args);
		} else {
			$self->async_processor->schedule_job($job, 0, @args);
		}
	} else {
		push @{$self->async_command_queue}, [$job, $delay, @args];
	}
}

sub schedule_gpc {
	my ($self, $gpc) = @_;
	# we must read the jobid, otherwise Thread::Pool will think that we don't want the results
	my $jobid = $self->processing_thread_pool->job($gpc);
	# $self->warn(1, ": scheduled job $jobid"); # DEBUG JOBS
	$self->scheduled_jobs->{$jobid} = 1;
}

sub init_processing_thread {
	my ($self) = @_;
	my %initialized_processors;
	for my $processor (values %{$self->processors}) {
		$self->warn(1, "initializing processor [" . $processor . "]");
		$processor->init_thread($self) unless exists $initialized_processors{"$processor"};
		$initialized_processors{"$processor"} = 1;
	}
}

sub process_gpc {
	my ($self, $gpc) = @_;
	# $self->warn(1, "got gpc in process: ", Dumper $gpc);
	$self->async_command_queue([]);

	my $uri = $gpc->{uri};
	if (exists $self->processors->{$uri->protocol}) {
		$self->warn(1, "processing gpc '" . $uri->as_string . "' with router [" . $self->processors->{$uri->protocol} . "]");
		return $gpc->{socket}, $self->async_command_queue, $self->processors->{$uri->protocol}->execute_gpc($gpc)
	} else {
		$self->warn(1, "no router found for protocol '" . $uri->protocol . "'");
		return $gpc->{socket}, $self->async_command_queue
	}
}





1;
