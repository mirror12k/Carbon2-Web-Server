package Carbon::Limestone::DatabaseClient;
use strict;
use warnings;

use feature 'say';

use Carp;

use Carbon::Limestone::Query;



sub new {
	my ($class, $database, $connection_or_manager) = @_;
	my $self = bless {}, $class;
	$self->{database} = $database // croak "database argument required";

	if (defined $connection_or_manager) {
		if ($connection_or_manager->isa('Carbon::Limestone::ClientConnection')) {
			$self->{database_connection} = $connection_or_manager;
		} elsif ($connection_or_manager->isa('Carbon::Limestone')) {
			$self->{database_manager} = $connection_or_manager;
		} else {
			croak "invalid connection_or_manager given: $connection_or_manager";
		}
	}

	return $self
}

sub database_type { die "unimplemented database_type in $_[0]" }

sub request {
	my ($self, %args) = @_;

	$args{method} = 'query';
	$args{database_type} = $self->database_type;
	my $query = Carbon::Limestone::Query->new(%args);

	if (defined $self->{database_manager}) {
		my $uri = Carbon::URI->parse("$self->{database}");
		return $self->{database_manager}->execute_gpc({ uri => $uri, data => $query });
	} elsif (defined $self->{database_connection}) {
		return $self->{database_connection}->query($self->{database}, $query);
	} else {
		croak "no database_manager or database_connection configured";
	}
}

1;
