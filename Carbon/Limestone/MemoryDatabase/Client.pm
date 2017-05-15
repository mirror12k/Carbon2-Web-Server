package Carbon::Limestone::MemoryDatabase::Client;
use parent 'Carbon::Limestone::DatabaseClient';
use strict;
use warnings;

use feature 'say';

use Carp;

use Carbon::Limestone::Query;



sub new {
	my ($class, @args) = @_;
	my $self = $class->SUPER::new(@args);

	return $self
}

sub database_type { 'Carbon::Limestone::MemoryDatabase' }

sub get {
	my ($self, $collection) = @_;

	return $self->request(
		type => 'get',
		collection => $collection,
	)
}

sub count {
	my ($self, $collection) = @_;

	return $self->request(
		type => 'count',
		collection => $collection,
	)
}

sub delete {
	my ($self, $collection) = @_;

	return $self->request(
		type => 'delete',
		collection => $collection,
	)
}

sub push {
	my ($self, $collection, @data) = @_;
	return $self->request(
		type => 'push',
		collection => $collection,
		data => \@data,
	)
}



1;
