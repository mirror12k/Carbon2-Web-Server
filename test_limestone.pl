#!/usr/bin/env perl
use strict;
use warnings;

use feature 'say';

use Data::Dumper;

use Carbon::Limestone;
use Carbon::URI;
use Carbon::Limestone::Query;
use Carbon::Limestone::MemoryDatabase::Client;



my $manager = Carbon::Limestone->new(debug => 1);

# my $res = $manager->execute_gpc({
# 	uri => Carbon::URI->parse('/my_memory_db'),
# 	data => Carbon::Limestone::Query->new(method => 'create', database_type => 'Carbon::Limestone::MemoryDatabase'),
# });

# connect a client to the database
my $db = Carbon::Limestone::MemoryDatabase::Client->new(database => '/my_memory_db', database_manager => $manager);

# put some documents into the collection
for (0 .. 10) {
	say Dumper $db->push('asdf', int rand 5);
}

# get document count
say Dumper $db->count('asdf');
# get all documents
say Dumper $db->get('asdf');
# delete the collection before leaving
say Dumper $db->delete('asdf');

$manager->store_databases;

