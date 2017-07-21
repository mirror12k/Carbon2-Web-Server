package Carbon::Limestone::DocumentDatabase::DocumentCollection;
use strict;
use warnings;

use feature 'say';

use threads;
use threads::shared;

use File::Path qw/ make_path remove_tree /;
use File::Slurper qw/ read_binary write_binary read_dir /;
use JSON;

use IO::File;


use Data::Dumper;

our $CHUNK_STRUCT_SIZE = 4;
our $CHUNK_STRUCT_ALIGN = 8;
our $CHUNK_STRUCT_ALIGN_MASK = 0xfffffff8;

our $DEFAULT_MEMORY_EXPANSION_AMOUNT = 1024 * 64;








sub new {
	my ($class, %args) = @_;
	my $self = bless {}, $class;

	$self->{collection_directory} = $args{collection_directory} // die "collection_directory argument required";

	if ($args{initialize}) {
		make_path($self->{collection_directory});
		$self->init_database_file;
	} else {
		$self->read_allocator_structure;
	}

	return $self
}

sub init_database_file {
	my ($self) = @_;

	$self->{allocator_structure} = shared_clone({
		max_free_chunks => 16,
		freelist => [],
		memory_size => 0,
		top_chunk => {
			size => 0,
			offset => 0,
			is_top => 1,
			in_use => 0,
		},
	});

	my $file_handle = IO::File->new("$self->{collection_directory}/__database_file", 'w');
	die "failed to create database collection file: '$self->{collection_directory}/__database_file': $!"
			unless defined $file_handle;

	$self->expand_database_memory($file_handle, $DEFAULT_MEMORY_EXPANSION_AMOUNT);
	$file_handle->close;
}

sub open_database_file {
	my ($self) = @_;

	my $file_handle = IO::File->new("$self->{collection_directory}/__database_file", 'r+');
	die "failed to open database collection file: '$self->{collection_directory}/__database_file': $!"
			unless defined $file_handle;
	return $file_handle
}

sub read_allocator_structure {
	my ($self) = @_;

	my $data = read_binary("$self->{collection_directory}/__allocator_structure.json");
	$self->{allocator_structure} = shared_clone(decode_json($data));
	say "read allocator_structure: ", Dumper $self->{allocator_structure};
}

sub write_allocator_structure {
	my ($self) = @_;

	say "wrote allocator_structure: ", Dumper $self->{allocator_structure};
	my $data = encode_json($self->{allocator_structure});
	write_binary("$self->{collection_directory}/__allocator_structure.json", $data);
}







sub read_chunk {
	my ($self, $file_handle, $offset) = @_;

	return $self->{allocator_structure}{top_chunk} if $offset == $self->{allocator_structure}{top_chunk}{offset};

	$file_handle->seek($offset, SEEK_SET);
	$file_handle->read(my $buffer, $CHUNK_STRUCT_SIZE);

	die "failed to read chunk structure at $offset ($file_handle)" unless defined $buffer and length $buffer == $CHUNK_STRUCT_SIZE;


	my %data;
	$data{size} = unpack 'L<', $buffer;
	$data{in_use} = $data{size} & 0x1;
	$data{is_top} = 0;
	$data{size} = $data{size} & $CHUNK_STRUCT_ALIGN_MASK;
	$data{offset} = $offset;

	# return $self->{allocator_structure}{top_chunk} if $data{is_top};

	return \%data
}

sub read_next_chunk {
	my ($self, $file_handle, $chunk) = @_;
	# say "read_next_chunk: $chunk->{offset} + $chunk->{size}";
	my $offset = $chunk->{offset} + $chunk->{size};

	return $self->read_chunk($file_handle, $offset)
}

sub read_chunk_data {
	my ($self, $file_handle, $chunk) = @_;

	my $data_size = $chunk->{size} - 4;
	my $data = '';
	$file_handle->seek($chunk->{offset}, SEEK_SET);
	while (length($data) < $data_size) {
		my $status = $file_handle->read($data, $data_size - length($data), length($data));
		die "error reading chunk data [$chunk->{offset} : $file_handle]: $!" unless defined $status;
	}

	return $data
}

sub write_chunk {
	my ($self, $file_handle, $chunk) = @_;

	my $size_field = ($chunk->{in_use} & 1) | $chunk->{size};
	my $data = pack 'L<', $size_field;
	
	$file_handle->seek($chunk->{offset}, SEEK_SET);
	$file_handle->print($data);
}

sub write_chunk_data {
	my ($self, $file_handle, $chunk, $data) = @_;

	$file_handle->seek($chunk->{offset} + $CHUNK_STRUCT_SIZE, SEEK_SET);
	$file_handle->print($data);
}

sub expand_database_memory {
	my ($self, $file_handle, $amount_memory) = @_;

	$file_handle->seek(0, SEEK_END);
	$file_handle->print("\x00" x $amount_memory);

	$self->{allocator_structure}{memory_size} += $amount_memory;
	$self->{allocator_structure}{top_chunk}{size} += $amount_memory;
	$self->write_allocator_structure;
	# $self->write_chunk($file_handle, $self->{allocator_structure}{top_chunk});
}

sub chop_chunk {
	my ($self, $file_handle, $chunk, $size) = @_;

	my %new_chunk;
	$new_chunk{size} = $chunk->{size} - $size;
	$new_chunk{offset} = $chunk->{offset} + $size;
	$new_chunk{in_use} = $chunk->{in_use};

	$chunk->{size} = $size;

	$self->write_chunk($file_handle, $chunk);
	$self->write_chunk($file_handle, \%new_chunk);

	return $chunk, \%new_chunk
}

sub allocate_chunk {
	my ($self, $file_handle, $size) = @_;

	# add size of header
	my $new_chunk_size = $size + $CHUNK_STRUCT_SIZE;
	# align size
	$new_chunk_size = ($new_chunk_size & $CHUNK_STRUCT_ALIGN_MASK) + $CHUNK_STRUCT_ALIGN
			if ($new_chunk_size % $CHUNK_STRUCT_ALIGN) > 0;

	say "allocating new chunk of size $new_chunk_size";

	# check free chunks to see if we can return an existing chunk
	foreach my $freelist_index (0 .. $#{$self->{allocator_structure}{freelist}}) {
		my $free_chunk = $self->{allocator_structure}{freelist}[$freelist_index];
		if ($free_chunk->{size} >= $new_chunk_size) {
			say "found suitable free chunk:", Dumper $free_chunk;
			$self->remove_chunk_from_freelist($freelist_index);
			$free_chunk = unshared_clone($free_chunk);

			# check if we need to slice up a big chunk or return as-is
			if ($free_chunk->{size} >= $new_chunk_size * 2) {
				say "chopping chunk down to size";
				my ($alloc_chunk, $chopped_chunk) = $self->chop_chunk($file_handle, $free_chunk, $new_chunk_size);
				$self->add_free_chunk($chopped_chunk);

				$alloc_chunk->{in_use} = 1;
				$self->write_chunk($file_handle, $alloc_chunk);

				return $alloc_chunk
			} else {
				my $alloc_chunk = $free_chunk;
				$alloc_chunk->{in_use} = 1;
				$self->write_chunk($file_handle, $alloc_chunk);

				return $alloc_chunk
			}
		}
	}

	my $top_chunk = $self->{allocator_structure}{top_chunk};
	# expand memory until top chunk has enough to support the new chunk
	while ($top_chunk->{size} < $new_chunk_size + $CHUNK_STRUCT_SIZE) {
		warn "allocating 64kb more memory in the database";
		$self->expand_database_memory($file_handle, $DEFAULT_MEMORY_EXPANSION_AMOUNT);
	}
	
	# carve out the new chunk from the top chunk
	my $new_chunk_offset = $top_chunk->{offset};

	$top_chunk->{size} -= $new_chunk_size;
	$top_chunk->{offset} += $new_chunk_size;
	$self->write_allocator_structure;

	my %new_chunk;
	$new_chunk{size} = $new_chunk_size;
	$new_chunk{offset} = $new_chunk_offset;
	$new_chunk{in_use} = 1;
	$self->write_chunk($file_handle, \%new_chunk);

	return \%new_chunk
}

sub chunk_freelist_index {
	my ($self, $chunk) = @_;

	foreach (0 .. $#{$self->{allocator_structure}{freelist}}) {
		if ($self->{allocator_structure}{freelist}[$_]{offset} == $chunk->{offset}) {
			return $_
		}
	}

	return -1
}

sub remove_chunk_from_freelist {
	my ($self, $freelist_index) = @_;

	@{$self->{allocator_structure}{freelist}} =
		map $self->{allocator_structure}{freelist}[$_], grep { $_ != $freelist_index } 0 .. $#{$self->{allocator_structure}{freelist}};
	# splice @{$self->{allocator_structure}{freelist}}, $freelist_index, 1;
	$self->write_allocator_structure;
}

sub coalesce_adjacent_chunk {
	my ($self, $file_handle, $chunk, $next_chunk) = @_;

	# remove the next chunk from the freelist if it is there
	my $freelist_index = $self->chunk_freelist_index($next_chunk);
	$self->remove_chunk_from_freelist($freelist_index) if $freelist_index != -1;

	# join and write the chunks
	$chunk->{size} += $next_chunk->{size};
	$self->write_chunk($file_handle, $chunk);
}

sub coalesce_top_chunk {
	my ($self, $chunk) = @_;

	my $top_chunk = $self->{allocator_structure}{top_chunk};
	$top_chunk->{size} += $chunk->{size};
	$top_chunk->{offset} = $chunk->{offset};

	$self->write_allocator_structure;
}

sub add_free_chunk {
	my ($self, $chunk) = @_;

	# add the new chunk to the freelist
	unshift @{$self->{allocator_structure}{freelist}}, shared_clone($chunk);
	# pop a chunk from the freelist if there are too many
	pop @{$self->{allocator_structure}{freelist}}
		if @{$self->{allocator_structure}{freelist}} >= $self->{allocator_structure}{max_free_chunks};

	$self->write_allocator_structure;
}

sub free_chunk {
	my ($self, $file_handle, $chunk) = @_;

	# mark it as unused
	$chunk->{in_use} = 0;
	$self->write_chunk($file_handle, $chunk);

	# check if we can coalesce the next chunk
	my $next_chunk = $self->read_next_chunk($file_handle, $chunk);
	until ($next_chunk->{is_top} or $next_chunk->{in_use}) {
		say "coalescing adjacent chunk";
		$self->coalesce_adjacent_chunk($file_handle, $chunk, $next_chunk);
		$next_chunk = $self->read_next_chunk($file_handle, $chunk);
	}

	if ($next_chunk->{is_top}) {
		say "coalescing top chunk";
		$self->coalesce_top_chunk($chunk);
	} else {
		say "adding chunk to free list";
		$self->add_free_chunk($chunk);
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
