package Carbon::AsyncProcessor;
use strict;
use warnings;

use feature qw/ say current_sub /;

use Time::HiRes qw/ usleep time /;



sub new {
	my ($class, %args) = @_;
	my $self = bless {}, $class;

	$self->scheduled_jobs([]);
	$self->delay($args{delay} // 50);

	return $self
}

sub scheduled_jobs { @_ > 1 ? $_[0]{scheduled_jobs} = $_[1] : $_[0]{scheduled_jobs} }
sub running { @_ > 1 ? $_[0]{running} = $_[1] : $_[0]{running} }
sub delay { @_ > 1 ? $_[0]{delay} = $_[1] : $_[0]{delay} }



sub schedule_job {
	my ($self, $callback, $infinite, @args) = @_;

	push @{$self->scheduled_jobs}, {
		callback => $callback,
		infinite => $infinite,
		args => \@args,
	};
}

sub schedule_delayed_job {
	my ($self, $callback, $delay, @args) = @_;

	my $start_time = time;
	$self->schedule_job(sub {
		if (time - $start_time >= $delay) {
			# warn "debug trigger time ", time, " sleeping";
			$callback->(@args);
		} else {
			# warn "debug time ", time, " sleeping";
			$self->schedule_job(__SUB__);
		}
	});
}

sub process_loop {
	my ($self) = @_;
	$self->running(1);
	while ($self->running and @{$self->scheduled_jobs}) {
		my $frame_start = time;
		my @running_jobs = @{$self->scheduled_jobs};
		@{$self->scheduled_jobs} = ();
		foreach my $job (@running_jobs) {
			$job->{callback}->(@{$job->{args}});
			push @{$self->scheduled_jobs}, $job if $job->{infinite};
		}
		my $frame_time = time - $frame_start;
		if ($self->delay / 1000 > $frame_time) {
			my $sleep_time = int (($self->delay / 1000 - $frame_time) * 1000000);
			# warn "frame time: ", $frame_time, ", sleeping: ", $sleep_time;
			usleep ($sleep_time);
		}
	}
}




1;
