package Carbon::Limestone::FileDatabase::Client;
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

sub database_type { 'Carbon::Limestone::FileDatabase' }

sub put {
	my ($self, $file, $data) = @_;

	return $self->request(
		type => 'put',
		file => $file,
		data => $data,
	)
}

sub delete {
	my ($self, $file) = @_;

	return $self->request(
		type => 'delete',
		file => $file,
	)
}

sub get {
	my ($self, $file) = @_;

	return $self->request(
		type => 'get',
		file => $file,
	)
}

sub exists {
	my ($self, $file) = @_;

	return $self->request(
		type => 'exists',
		file => $file,
	)
}

sub glob {
	my ($self, $file) = @_;

	return $self->request(
		type => 'glob',
		file => $file,
	)
}



1;
