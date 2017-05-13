package Carbon::Limestone::MemoryDatabase;
use parent 'Carbon::Limestone::Database';
use strict;
use warnings;

use feature 'say';
use File::Path qw/ make_path remove_tree /;
use File::Slurper qw/ read_binary write_binary read_dir /;
use JSON;






sub database_type { 'Carbon::Limestone::MemoryDatabase' }


sub load_from_filesystem {
	my ($self) = @_;
	foreach my $key (grep /\A[^\.]/, read_dir($self->path)) {
		my $data = read_binary($self->path . "/$key");
		$self->{collections}{$key} = decode_json($data);
	}
}

sub store_to_filesystem {
	my ($self) = @_;
	foreach my $key (sort keys %{$self->{collections}}) {
		my $data = encode_json($self->{collections}{$key});
		write_binary($self->path . "/$key", $data);
	}
}


sub create {
	my ($class, @args) = @_;
	my ($self) = $class->SUPER::create(@args);

	$self->{collections} = {};

	return $self
}



1;
