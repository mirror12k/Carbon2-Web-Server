package Carbon2;

use strict;
use warnings;

use feature 'say';


use threads;
use IO::Select;
use IO::Pipe;
use Thread::Pool;
use Thread::Queue;
use Time::HiRes qw/ usleep /;

use FreezeThaw qw/ freeze thaw /;
use Carp;

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

sub thread_id { @_ > 1 ? $_[0]{carbon_server__thread_id} = $_[1] : $_[0]{carbon_server__thread_id} }
sub server_running { @_ > 1 ? $_[0]{carbon_server__running} = $_[1] : $_[0]{carbon_server__running} }

sub socket_selector { @_ > 1 ? $_[0]{carbon_server__socket_selector} = $_[1] : $_[0]{carbon_server__socket_selector} }
sub server_socket_queue { @_ > 1 ? $_[0]{carbon_server__server_socket_queue} = $_[1] : $_[0]{carbon_server__server_socket_queue} }
sub server_socket_back_queue { @_ > 1 ? $_[0]{carbon_server__server_socket_back_queue} = $_[1] : $_[0]{carbon_server__server_socket_back_queue} }
sub connection_thread_pool { @_ > 1 ? $_[0]{carbon_server__connection_thread_pool} = $_[1] : $_[0]{carbon_server__connection_thread_pool} }
sub processing_thread_pool { @_ > 1 ? $_[0]{carbon_server__processing_thread_pool} = $_[1] : $_[0]{carbon_server__processing_thread_pool} }
sub scheduled_jobs { @_ > 1 ? $_[0]{carbon_server__scheduled_jobs} = $_[1] : $_[0]{carbon_server__scheduled_jobs} }

sub receivers { @_ > 1 ? $_[0]{carbon_server__receivers} = $_[1] : $_[0]{carbon_server__receivers} }
sub receiver_map { @_ > 1 ? $_[0]{carbon_server__receiver_map} = $_[1] : $_[0]{carbon_server__receiver_map} }
sub processors { @_ > 1 ? $_[0]{carbon_server__processors} = $_[1] : $_[0]{carbon_server__processors} }
sub connection_processing_workers { @_ > 1 ? $_[0]{carbon_server__connection_processing_workers} = $_[1] : $_[0]{carbon_server__connection_processing_workers} }
sub request_processing_workers { @_ > 1 ? $_[0]{carbon_server__request_processing_workers} = $_[1] : $_[0]{carbon_server__request_processing_workers} }

sub multiplexer_thread { @_ > 1 ? $_[0]{carbon_server__multiplexer_thread} = $_[1] : $_[0]{carbon_server__multiplexer_thread} }
sub multiplexer_pipe { @_ > 1 ? $_[0]{carbon_server__multiplexer_pipe} = $_[1] : $_[0]{carbon_server__multiplexer_pipe} }
sub processing_thread_pipes { @_ > 1 ? $_[0]{carbon_server__processing_thread_pipes} = $_[1] : $_[0]{carbon_server__processing_thread_pipes} }
sub connection_thread_pipes { @_ > 1 ? $_[0]{carbon_server__connection_thread_pipes} = $_[1] : $_[0]{carbon_server__connection_thread_pipes} }
sub processing_pipe_queue { @_ > 1 ? $_[0]{carbon_server__processing_pipe_queue} = $_[1] : $_[0]{carbon_server__processing_pipe_queue} }
sub connection_pipe_queue { @_ > 1 ? $_[0]{carbon_server__connection_pipe_queue} = $_[1] : $_[0]{carbon_server__connection_pipe_queue} }

sub connection_thread_input_pipe { @_ > 1 ? $_[0]{carbon_server__connection_thread_input_pipe} = $_[1] : $_[0]{carbon_server__connection_thread_input_pipe} }
sub processing_thread_output_pipe { @_ > 1 ? $_[0]{carbon_server__processing_thread_output_pipe} = $_[1] : $_[0]{carbon_server__processing_thread_output_pipe} }

sub connection_readable_selector { @_ > 1 ? $_[0]{carbon_server__connection_readable_selector} = $_[1] : $_[0]{carbon_server__connection_readable_selector} }
sub connection_writable_selector { @_ > 1 ? $_[0]{carbon_server__connection_writable_selector} = $_[1] : $_[0]{carbon_server__connection_writable_selector} }
# sub async_processor { @_ > 1 ? $_[0]{carbon_server__async_processor} = $_[1] : $_[0]{carbon_server__async_processor} }
sub async_command_queue { @_ > 1 ? $_[0]{carbon_server__async_command_queue} = $_[1] : $_[0]{carbon_server__async_command_queue} }
sub active_connections { @_ > 1 ? $_[0]{carbon_server__active_connections} = $_[1] : $_[0]{carbon_server__active_connections} }





sub warn {
	my ($self, $level, @args) = @_;
	if ($self->{debug} and $self->{debug} <= $level) {
		$self->onwarn->("[". (caller)[0] ."][" . $self->thread_id . "] ", @args, "\n");
	}
}

sub die {
	my ($self, @args) = @_;
	$self->onerror->("[". (caller)[0] ."][$self][" . $self->thread_id . "] ", @args, "\n");
	CORE::die "returning from onerror is not allowed";
}


sub start {
	my ($self) = @_;

	$self->server_socket_back_queue(Thread::Queue->new);
	$self->thread_id('main');

	$self->start_server_sockets;
	# $self->start_thread_pool;
	$self->start_multiplexer_thread;

	$self->listen_accept_server_loop;

	$self->cleanup;
}

sub start_multiplexer_thread {
	my ($self) = @_;

	$self->multiplexer_pipe(IO::Pipe->new);

	$self->multiplexer_thread(threads->create(sub {
		$self->multiplexer_pipe->reader;
		$self->thread_id('multiplexer_thread');

		$self->start_thread_pool;
		$self->multiplexer_thread_loop;

		$self->warn(1, "shutting down connection thread pool");
		$self->connection_thread_pool->shutdown;
		$self->warn(1, "shutting down processing thread pool");
		$self->processing_thread_pool->shutdown;
	}));

	$self->multiplexer_pipe->writer;
	$self->multiplexer_pipe->autoflush(1);
}

sub start_thread_pool {
	my ($self) = @_;

	$self->processing_thread_pipes({ map { ("processing_thread_$_" => IO::Pipe->new) } 1 .. $self->request_processing_workers });
	$self->processing_pipe_queue(Thread::Queue->new);
	$self->processing_pipe_queue->enqueue("processing_thread_$_") for 1 .. $self->request_processing_workers;

	$self->connection_thread_pipes({ map { ("connection_thread_$_" => IO::Pipe->new) } 1 .. $self->request_processing_workers });
	$self->connection_pipe_queue(Thread::Queue->new);
	$self->connection_pipe_queue->enqueue("connection_thread_$_") for 1 .. $self->request_processing_workers;

	$self->processing_thread_pool(Thread::Pool->new({
		workers => $self->request_processing_workers,
		pre => sub {
			eval { $self->init_processing_thread(@_) };
			$self->warn(1, "processing thread died during initialization: $@") if $@;
		},
		do => sub {
			my ($gpc) = @_;
			my @ret = eval { $self->do_processing_thread($gpc); };
			$self->warn(1, "processing thread during do-operation: $@") if $@;

			return @ret
		},
		post => sub {
			$self->warn(1, "closing processing thread");
		}
	}));

	$self->connection_thread_pool(Thread::Pool->new({
		workers => $self->connection_processing_workers,
		pre => sub {
			eval { $self->init_connection_thread(@_) };
			$self->warn(1, "connection thread died during initialization: $@") if $@;

			$self->warn(1, "starting connection thread");
			my $leave = 0;
			do {
				eval { $self->connection_thread_loop; $leave = 1; };
				$self->warn(1, "connection thread died of $@") if $@;
			} until ($leave);
		},
		do => sub {},
		post => sub {
			$self->warn(1, "closing connection thread");
		}
	}));

	$_->reader for values %{$self->processing_thread_pipes};

	$_->writer for values %{$self->connection_thread_pipes};
	$_->autoflush(1) for values %{$self->connection_thread_pipes};

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

	my %socket_cache;
	# main listen-accept loop
	$self->server_running(1);
	while ($self->server_running) {
		# say "in loop";
		foreach my $socket ($self->socket_selector->can_read) {
			my $new_socket = $socket->accept;
			$self->warn(1, "got connection $new_socket (" . fileno ($new_socket) . ")");
			$new_socket->blocking(0); # set it to non-blocking

			my $packet = package_packet(socket => "$socket", "$new_socket", fileno $new_socket);
			$packet = package_packet(socket => $packet);
			$self->multiplexer_pipe->print($packet);

			$socket_cache{"$new_socket"} = $new_socket;
		}
		# say "leaving loop";

		# receive any sockets which are ready for garbage collection
		while (defined (my $socket_id = $self->server_socket_back_queue->dequeue_nb)) {
			delete $socket_cache{"$socket_id"};
		}
	}

}

sub multiplexer_thread_loop {
	my ($self) = @_;

	my $reader_selector = IO::Select->new;
	$reader_selector->add($self->multiplexer_pipe);
	$reader_selector->add($_) for values %{$self->processing_thread_pipes};

	$self->server_running(1);
	while ($self->server_running) {
		foreach my $handle ($reader_selector->can_read) {
			$handle->read(my $buf, 4);
			my $data_length = unpack 'N', $buf;
			my $data = '';
			$handle->read($data, $data_length - length $data, length $data) until length $data >= $data_length;

			my ($instruction, @args) = thaw $data;
			# say "got instruction packet: $instruction";
			if ($instruction eq 'packet') {
				my ($destination, $packet) = @args;
				# pass the packet on to its destination
				$self->connection_thread_pipes->{$destination}->print($packet);
			} elsif ($instruction eq 'socket') {
				my ($packet) = @args;
				# choose a connection thread at random to process the connection
				my $thread_id = (keys %{$self->connection_thread_pipes})[int rand scalar keys %{$self->connection_thread_pipes}];
				# send the packet to it
				$self->connection_thread_pipes->{$thread_id}->print($packet);
			} elsif ($instruction eq 'end') {
				$_->print("$buf$data") for values %{$self->connection_thread_pipes};
				$self->server_running(0);
			} else {
				$self->die("invalid packet instruction: $instruction");
			}
		}
	}
}

sub connection_thread_loop {
	my ($self) = @_;

	$self->connection_readable_selector(IO::Select->new);
	$self->connection_writable_selector(IO::Select->new);
	$self->active_connections({});
	$self->scheduled_jobs({});
	# $self->async_processor(Carbon::AsyncProcessor->new(delay => 50));

	$self->connection_readable_selector->add($self->connection_thread_input_pipe);

	$self->server_running(1);
	while ($self->server_running) {
		my ($readable, $writable) = IO::Select->select($self->connection_readable_selector, $self->connection_writable_selector);

		foreach my $handle (@$writable) {
			my $connection = $self->active_connections->{"$handle"};
			# $self->warn(1, "writing from buffer of $handle");
			$connection->write_buffered;
			if (length $connection->{write_buffer} == 0) {
				# $self->warn(1, "removing $handle from writable due to empty buffer");
				$self->connection_writable_selector->remove($handle);
			}
		}

		foreach my $handle (@$readable) {
			if ($handle == $self->connection_thread_input_pipe) {
				$handle->read(my $buf, 4);
				my $data_length = unpack 'N', $buf;
				my $data = '';
				$handle->read($data, $data_length - length $data, length $data) until length $data >= $data_length;

				my ($instruction, @args) = thaw($data);

				if ($instruction eq 'end') {
					# say "debug end in connection thread";
					$self->server_running(0);
				} elsif ($instruction eq 'socket') {
					my ($parent_socket, $socket_id, $socket_no) = @args;
					$self->warn(1, "got instruction: $parent_socket, $socket_id, $socket_no");
					# reinflate the socket from it's fileno
					my $receiver = $self->receiver_map->{$parent_socket};
					my $socket = $receiver->restore_socket($socket_no);
					# notify the listen-accept loop that we have received the socket and that it can safely garbage collect it
					$self->server_socket_back_queue->enqueue($socket_id);

					# start the connection
					my $connection = $receiver->start_connection($self, $socket);
					$self->add_connection($socket, $connection);

				} elsif ($instruction eq 'result') {
					my ($jobid) = @args;
					if (exists $self->scheduled_jobs->{$jobid}) {
						my $socket = $self->scheduled_jobs->{$jobid};
						delete $self->scheduled_jobs->{$jobid};
						# $self->warn(1, ": got result from job $jobid"); # DEBUG JOBS
						my ($async_commands, @results) = $self->processing_thread_pool->result($jobid);

						# queue up any scheduled async jobs that the gpc produced
						foreach my $command (@$async_commands) {
							my ($callback, $delay, @args) = @$command;
							# $self->warn(1, "got async command: @$command");
							# we need to restore the callback since passing around code refs is not allowed
							$callback = \&{$callback};
							$self->schedule_async_job($callback, $delay, @args);
						}

						# reclaim any socket whose job has completed
						if (exists $self->active_connections->{"$socket"}) {
							my $connection = $self->active_connections->{"$socket"};
							# if the connection is still alive
							$connection->result(@results) if $connection;

							# $self->warn(1, "adding $handle to writable");
							$self->connection_writable_selector->add($connection->{socket});
						} else {
							$self->warn(1, "got result for $socket but connection is already closed");
						}
					}
				} else {
					$self->die("invalid instruction in connection thread: $instruction");
				}

			} else {
				my $connection = $self->active_connections->{"$handle"};
				$connection->read_buffered;
			}
		}
	}
}

sub do_processing_thread {
	my ($self, $gpc) = @_;

	# $self->warn(1, "got request for $gpc->{return_thread_id}"); # DEBUG JOBS
	my @ret = eval { $self->process_gpc($gpc) };
	$self->warn(1, "processing thread died: $@") if $@;

	my $packet = package_packet(result => Thread::Pool->jobid);
	$packet = package_packet(packet => $gpc->{return_thread_id}, $packet);

	$self->processing_thread_output_pipe->print($packet);
	# $self->warn(1, "got response for $gpc->{return_thread_id}: @ret"); # DEBUG JOBS

	return @ret
}




sub package_packet {
	my $data = freeze(@_);
	my $data_length = pack 'N', length $data;
	my $packet = "$data_length$data";

	return $packet
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

sub cleanup {
	my ($self) = @_;
	$self->warn(1, "cleaning up...");

	for my $receiver (@{$self->receivers}) {
		$receiver->shutdown;
	}

	my $packet = package_packet('end');
	$self->multiplexer_pipe->print($packet);
	$self->multiplexer_thread->join;
	# $self->server_socket_queue->end;
	# $_->print("end_") foreach values %{$self->{test_pipes}};
	# $_->print("end_") foreach values %{$self->{test_pipes}};
	# $self->{test_pipe}->close;
	# $self->warn(1, "shutting down connection thread pool");
	# $self->connection_thread_pool->shutdown;
	# $self->warn(1, "shutting down processing thread pool");
	# $self->processing_thread_pool->shutdown;
}

sub recast_connection {
	my ($self, $connection_socket, $new_connection) = @_;

	$self->warn(1, "recast socket $connection_socket as $new_connection");
	$self->active_connections->{"$connection_socket"} = $new_connection;
}

sub add_connection {
	my ($self, $connection_socket, $connection) = @_;

	$self->warn(1, "new socket $connection_socket");
	$self->connection_readable_selector->add($connection_socket);
	$self->active_connections->{"$connection_socket"} = $connection;
}

sub remove_connection {
	my ($self, $connection_socket) = @_;

	$self->warn(1, "closing socket $connection_socket");
	$self->connection_readable_selector->remove($connection_socket);
	$self->active_connections->{"$connection_socket"}->close;
	delete $self->active_connections->{"$connection_socket"};
}

# sub schedule_async_job {
# 	my ($self, $job, $delay, @args) = @_;

# 	# in connection thread context, we just put it directly into the async_processor
# 	if (defined $self->async_processor) {
# 		if (defined $delay) {
# 			$self->async_processor->schedule_delayed_job($job, $delay, @args);
# 		} else {
# 			$self->async_processor->schedule_job($job, 0, @args);
# 		}
# 	} else {
# 		push @{$self->async_command_queue}, [$job, $delay, @args];
# 	}
# }

sub schedule_gpc {
	my ($self, $gpc) = @_;

	$gpc->{return_thread_id} = $self->thread_id;

	# we must read the jobid, otherwise Thread::Pool will think that we don't want the results
	my $jobid = $self->processing_thread_pool->job($gpc);
	# $self->warn(1, ": scheduled job $jobid"); # DEBUG JOBS
	$self->scheduled_jobs->{$jobid} = $gpc->{socket};
}

sub init_connection_thread {
	my ($self) = @_;

	# receive our unique thread id and get our assigned pipe
	$self->thread_id($self->connection_pipe_queue->dequeue);
	$self->connection_thread_input_pipe($self->connection_thread_pipes->{$self->thread_id});
	$self->connection_thread_input_pipe->reader;
}

sub init_processing_thread {
	my ($self) = @_;

	# receive our unique thread id and get our assigned pipe
	$self->thread_id($self->processing_pipe_queue->dequeue);
	$self->processing_thread_output_pipe($self->processing_thread_pipes->{$self->thread_id});
	$self->processing_thread_output_pipe->writer;
	$self->processing_thread_output_pipe->autoflush(1);

	# initialize all processors so that they can begin thread-local loading
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
		return $self->async_command_queue, $self->processors->{$uri->protocol}->execute_gpc($gpc)
	} else {
		$self->warn(1, "no router found for protocol '" . $uri->protocol . "'");
		return $self->async_command_queue
	}
}





1;
