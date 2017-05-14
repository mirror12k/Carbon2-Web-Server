package Carbon::Limestone::MemoryDatabase::Client;
use strict;
use warnings;

use feature 'say';

use Carp;

use Carbon::Limestone::Query;



sub new {
	my ($class, %args) = @_;
	my $self = bless {}, $class;
	$self->{database} = $args{database} // croak "database argument required";
	$self->{database_connection} = $args{database_connection};
	$self->{database_manager} = $args{database_manager};

	return $self
}


sub request {
	my ($self, $query) = @_;

	if (defined $self->{database_manager}) {
		return $self->{database_manager}->execute_gpc({ uri => Carbon::URI->parse("$self->{database}"), data => $query });
	} elsif (defined $self->{database_connection}) {
		return $self->{database_connection}->query($self->{database}, $query);
	} else {
		croak "no database_manager or database_connection configured";
	}
}


sub get {
	my ($self, $collection) = @_;

	return $self->request(Carbon::Limestone::Query->new(
		method => 'query',
		database_type => 'Carbon::Limestone::MemoryDatabase',
		type => 'get',
		collection => $collection,
	))
}

sub count {
	my ($self, $collection) = @_;

	return $self->request(Carbon::Limestone::Query->new(
		method => 'query',
		database_type => 'Carbon::Limestone::MemoryDatabase',
		type => 'count',
		collection => $collection,
	))
}

sub delete {
	my ($self, $collection) = @_;

	return $self->request(Carbon::Limestone::Query->new(
		method => 'query',
		database_type => 'Carbon::Limestone::MemoryDatabase',
		type => 'delete',
		collection => $collection,
	))
}

sub push {
	my ($self, $collection, @data) = @_;
	return $self->request(Carbon::Limestone::Query->new(
		method => 'query',
		database_type => 'Carbon::Limestone::MemoryDatabase',
		type => 'push',
		collection => $collection,
		data => \@data,
	))
}



1;
