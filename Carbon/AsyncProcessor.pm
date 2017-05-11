package Carbon::AsyncProcessor;
use strict;
use warnings;

use feature 'say';

use Time::HiRes 'usleep';



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
	my ($self, $callback, $infinite) = @_;

	push @{$self->scheduled_jobs}, {
		callback => $callback,
		infinite => $infinite,
	};
}

sub process_loop {
	my ($self) = @_;
	$self->running(1);
	while ($self->running and @{$self->scheduled_jobs}) {
		my @running_jobs = @{$self->scheduled_jobs};
		@{$self->scheduled_jobs} = ();
		foreach my $job (@running_jobs) {
			$job->{callback}->();
			push @{$self->scheduled_jobs}, $job if $job->{infinite};
		}
		usleep ($self->delay * 1000);
	}
}




1;
