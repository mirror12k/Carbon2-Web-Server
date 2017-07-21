#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use Data::Dumper;

use Carbon::Limestone;
use Carbon::URI;
use Carbon::Limestone::Query;
use Carbon::Limestone::MemoryDatabase::Client;
use Carbon::Limestone::FileDatabase::Client;
use Carbon::Limestone::ClientConnection;
use Carbon::Limestone::DocumentDatabase::DocumentCollection;



my $collection = Carbon::Limestone::DocumentDatabase::DocumentCollection->new(
	collection_directory => 'test_collection',
	# initialize => 1,
);
my $handle = $collection->open_database_file;


# my $chunk = $collection->allocate_chunk($handle, 30);
# say "got chunk: ", Dumper $chunk;

# my $chunk2 = $collection->allocate_chunk($handle, 15);
# say "got chunk2: ", Dumper $chunk2;

# $collection->free_chunk($handle, $chunk);


# my $chunk3 = $collection->allocate_chunk($handle, 4);
# say "got chunk3: ", Dumper $chunk3;




# fuzzing routine to test the robustness of the system by repeatedly allocating and deallocating thousands of blocks
my @blocks;

foreach (0 .. 4096) {
	if (0 == int rand 2) {
		my $size = 1 + int rand 1000;
		my $block = $collection->allocate_chunk($handle, $size);
		say "allocated $size block [$block->{offset}:$block->{size}]";
		push @blocks, $block;
	} else {
		next unless @blocks;
		my $index = int rand @blocks;
		my ($block) = splice @blocks, $index, 1;
		say "freeing block [$block->{offset}:$block->{size}]";
		$collection->free_chunk($handle, $block);
	}
}

$collection->free_chunk($handle, $_) foreach @blocks;

say "ending allocator_structure:", Dumper $collection->{allocator_structure};

