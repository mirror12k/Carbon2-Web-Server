package Carbon::Limestone::MemoryDatabase;
use parent 'Carbon::Limestone::Database';
use strict;
use warnings;

use threads;
use threads::shared;
use feature 'say';

use File::Path qw/ make_path remove_tree /;
use File::Slurper qw/ read_binary write_binary read_dir /;
use JSON;

use Carbon::Limestone::Response;



sub new {
	my ($class, $path) = @_;
	my $self = $class->SUPER::new($path);

	$self->{collections} = shared_clone({});

	return $self
}



sub database_type { 'Carbon::Limestone::MemoryDatabase' }


sub load_from_filesystem {
	my ($self) = @_;
	foreach my $key (grep /\A[^\.]/, read_dir($self->path)) {
		my $data = read_binary($self->path . "/$key");
		$self->{collections}{$key} = shared_clone(decode_json($data));
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

	$self->{collections} = shared_clone({});

	return $self
}

sub execute_query {
	my ($self, $query) = @_;

	if ($query->{type} eq 'push') {
		return $self->lock_all_edits(sub {
			$self->{collections}{$query->{collection}} //= shared_clone([]);

			return Carbon::Limestone::Response->new(status => 'success',
				data => (push @{$self->{collections}{$query->{collection}}}, map shared_clone($_), @{$query->{data}}));
		});

	} elsif ($query->{type} eq 'delete') {
		return $self->lock_all_edits(sub {
			if (exists $self->{collections}{$query->{collection}}) {
				delete $self->{collections}{$query->{collection}};
				remove_tree($self->path . "/$query->{collection}");
			}

			return Carbon::Limestone::Response->new(status => 'success');
		});

	} elsif ($query->{type} eq 'get') {
		return Carbon::Limestone::Response->new(status => 'success',
				data => unshared_clone($self->{collections}{$query->{collection}} // []));

	} elsif ($query->{type} eq 'count') {
		return Carbon::Limestone::Response->new(status => 'success',
				data => scalar @{$self->{collections}{$query->{collection}}});

	}
}

sub unshared_clone {
	my ($data) = @_;

	if (ref $data eq 'HASH') {
		return { map { $_ => unshared_clone($data->{$_}) } keys %$data }
	} elsif (ref $data eq 'ARRAY') {
		return [ map unshared_clone($_), @$data ]
	} else {
		return $data
	}
}



1;
