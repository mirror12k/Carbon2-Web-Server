package Carbon::Limestone::FileDatabase;
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

	return $self
}



sub database_type { 'Carbon::Limestone::FileDatabase' }


sub load_from_filesystem {
	my ($self) = @_;
}

sub store_to_filesystem {
	my ($self) = @_;
}


sub create {
	my ($class, @args) = @_;
	my ($self) = $class->SUPER::create(@args);

	return $self
}

sub execute_query {
	my ($self, $query) = @_;

	if ($query->{type} eq 'put') {
		my $filepath = $self->sanitize_filepath($self->path . "/$query->{file}");
		return $self->lock_all_edits(sub {
			make_path($filepath =~ s/\/[^\/]*\Z/\//sr);
			write_binary($filepath, "$query->{data}");
			return Carbon::Limestone::Response->new(status => 'success');
		});

	} elsif ($query->{type} eq 'delete') {
		my $filepath = $self->sanitize_filepath($self->path . "/$query->{file}");
		return $self->lock_all_edits(sub {
			if (-e $filepath) {
				remove_tree($filepath);
				return Carbon::Limestone::Response->new(status => 'success');
			} else {
				return Carbon::Limestone::Response->new(status => 'error', error => 'file not found');
			}
		});

	} elsif ($query->{type} eq 'get') {
		my $filepath = $self->sanitize_filepath($self->path . "/$query->{file}");
		return $self->lock_all_edits(sub {
			if (-e -f $filepath) {
				return Carbon::Limestone::Response->new(status => 'success', data => read_binary($filepath));
			} elsif (-e $filepath) {
				return Carbon::Limestone::Response->new(status => 'error', error => 'not a file');
			} else {
				return Carbon::Limestone::Response->new(status => 'error', error => 'file not found');
			}
		});

	} elsif ($query->{type} eq 'exists') {
		my $filepath = $self->sanitize_filepath($self->path . "/$query->{file}");
		return $self->lock_all_edits(sub {
			if (-e $filepath) {
				return Carbon::Limestone::Response->new(status => 'success', data => 1);
			} else {
				return Carbon::Limestone::Response->new(status => 'success', data => 0);
			}
		});

	} elsif ($query->{type} eq 'glob') {
		my $filepath = $self->sanitize_filepath($self->path . "/$query->{file}");
		$filepath = $self->escape_fileglob($filepath);
		my $prefix = $self->path . '/';
		return $self->lock_all_edits(sub {
			return Carbon::Limestone::Response->new(status => 'success',
					data => [ map { substr $_, length $prefix } glob "'$filepath'" ]);
		});
	}
}

sub sanitize_filepath {
	my ($self, $filepath) = @_;
	$filepath =~ s/\/\.\.(?=\/|\Z)//g;
	return $filepath
}

sub escape_fileglob {
	my ($self, $fileglob) = @_;
	$fileglob =~ s/([\\'])/\\$1/g;
	return $fileglob
}



1;
