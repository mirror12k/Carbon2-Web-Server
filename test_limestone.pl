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



# my $manager = Carbon::Limestone->new(debug => 1);
my $connection = Carbon::Limestone::ClientConnection->new(uri => 'limestone://localhost');
$connection->connect;

# my $res = $manager->execute_gpc({
# 	uri => Carbon::URI->parse('/my_memory_db'),
# 	data => Carbon::Limestone::Query->new(method => 'create', database_type => 'Carbon::Limestone::MemoryDatabase'),
# });
# say Dumper $res;

# my $res = $connection->query(
# 	'/my_file_db',
# 	Carbon::Limestone::Query->new(method => 'create', database_type => 'Carbon::Limestone::FileDatabase'),
# );
# say Dumper $res;


# connect a client to the database
# my $db = Carbon::Limestone::MemoryDatabase::Client->new(database => '/my_memory_db', database_manager => $manager);
my $db = Carbon::Limestone::MemoryDatabase::Client->new('/my_memory_db' => $connection);

# put some documents into the collection
for (0 .. 100) {
	say Dumper $db->push('asdf', int rand 5);
}

# get document count
say Dumper $db->count('asdf');
# get all documents
say Dumper $db->get('asdf');
# delete the collection before leaving
say Dumper $db->delete('asdf');


# # connect a FileDatabase client to the database
# # my $db = Carbon::Limestone::FileDatabase::Client->new(database => '/my_file_db', database_manager => $manager);
# my $db = Carbon::Limestone::FileDatabase::Client->new('/my_file_db' => $connection);


# # put a document
# say Dumper $db->put('my_files/asdf.txt', "hello world!");
# # get the contents of my file
# say Dumper $db->get('my_files/asdf.txt');
# # list all of my files using a glob
# say Dumper $db->glob('my_files/*');
# # check if the file exists
# say Dumper $db->exists('my_files/asdf.txt');
# # delete the whole directory
# say Dumper $db->delete('my_files');
# # check if the file exists after deletion
# say Dumper $db->exists('my_files/asdf.txt');





# $manager->store_databases;

