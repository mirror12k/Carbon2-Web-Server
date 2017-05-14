package Carbon::Limestone::Database;
use strict;
use warnings;

use threads;
use threads::shared;
use feature 'say';

use File::Path qw/ make_path remove_tree /;



sub new {
	my ($class, $path) = @_;
	my $self = bless {}, $class;
	$self = share($self);

	$self->path($path);

	return $self
}


sub database_type { die "unimplemented database_type" }
sub path { @_ > 1 ? $_[0]{path} = $_[1] : $_[0]{path} }


sub load_from_filesystem {
	my ($self) = @_;
	die "unimplemented load_from_filesystem in $self";
}

sub store_to_filesystem {
	my ($self) = @_;
	die "unimplemented store_to_filesystem in $self";
}

sub lock_all_edits {
	my ($self, $callback) = @_;
	lock($self);
	return $callback->();
}

sub create {
	my ($class, $path) = @_;
	my $self = $class->new($path);
	make_path($self->path);
	return $self
}

sub delete {
	my ($self, $path) = @_;
	remove_tree($path);
}

sub execute_query {
	my ($self, $query) = @_;
	die "unimplemented execute_query in $self";
}





1;
