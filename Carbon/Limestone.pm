#!/usr/bin/env perl
package Carbon::Limestone;
use parent 'Carbon::Processor';

use strict;
use warnings;

use feature 'say';

use threads::shared 'share';
use File::Path qw/ make_path remove_tree /;
use File::Slurper qw/ read_binary write_binary read_dir /;
use JSON;

use Carp;
use Data::Dumper;

use Carbon::URI;
use Carbon::Limestone::Query;
use Carbon::Limestone::Response;

use Carbon::Limestone::MemoryDatabase;



sub new ($%) {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	$self->debug($args{debug} // 0);
	$self->onwarn($args{onwarn} // \&CORE::warn);
	$self->onerror($args{onerror} // \&Carp::confess);

	$self->databases_path($args{databases_path} // 'limestone_db');
	$self->databases($args{databases} // {});
	share($self->databases);

	if (-e -f $self->databases_path . "/__limestone_db.json") {
		$self->load_databases;
	} else {
		make_path($self->databases_path);
		$self->config({
			databases => {},
		});
	}
	share($self->config);

	return $self
}

sub warn {
	my ($self, $level, @args) = @_;
	if ($self->{debug} and $self->{debug} <= $level) {
		$self->onwarn->("[". (caller)[0] ."] ", @args, "\n");
	}
}

sub die {
	my ($self, @args) = @_;
	$self->onerror->("[". (caller)[0] ."][$self] ", @args);
	CORE::die "returning from onerror is not allowed";
}

sub debug { @_ > 1 ? $_[0]{debug} = $_[1] : $_[0]{debug} }
sub onwarn { @_ > 1 ? $_[0]{carbon_server__onwarn} = $_[1] : $_[0]{carbon_server__onwarn} }
sub onerror { @_ > 1 ? $_[0]{carbon_server__onerror} = $_[1] : $_[0]{carbon_server__onerror} }

sub config { @_ > 1 ? $_[0]{limestone__config} = $_[1] : $_[0]{limestone__config} }
sub databases { @_ > 1 ? $_[0]{limestone__databases} = $_[1] : $_[0]{limestone__databases} }
sub databases_path { @_ > 1 ? $_[0]{limestone__databases_path} = $_[1] : $_[0]{limestone__databases_path} }

sub load_config {
	my ($self) = @_;

	$self->config(decode_json(read_binary($self->databases_path . '/__limestone_db.json')));
	share($self->config);
}

sub load_databases {
	my ($self) = @_;

	$self->warn(1, "loading databases from " . $self->databases_path);
	$self->load_config;
	foreach my $database (keys %{$self->config->{databases}}) {
		my $class = $self->config->{databases}{$database}{database_type};
		my $path = $self->databases_path . $database;
		$self->warn(1, "loading $class database $path");
		$self->databases->{$database} = $class->new($path);
		$self->databases->{$database}->load_from_filesystem;
	}
}

sub store_config {
	my ($self) = @_;
	write_binary($self->databases_path . '/__limestone_db.json', encode_json($self->config));
}

sub store_databases {
	my ($self) = @_;

	$self->warn(1, "storing databases to " . $self->databases_path);
	$self->store_config;
	foreach my $database (keys %{$self->config->{databases}}) {
		my $class = $self->config->{databases}{$database}{database_type};
		my $path = $self->databases_path . $database;
		$self->warn(1, "storing $class database $path");
		$self->databases->{$database}->store_to_filesystem;
	}
}


sub execute_gpc {
	my ($self, $gpc) = @_;

	my $uri = $gpc->{uri};
	my $req = $gpc->{data};

	$self->warn(1, "got $req->{method} request");
	if ($req->{method} eq 'create') {
		return Carbon::Limestone::Response->new(status => 'error', error => 'database already exists')
				if exists $self->databases->{$uri->path};
		return Carbon::Limestone::Response->new(status => 'error', error => 'incorrect database type')
				unless exists $req->{database_type};

		$self->databases->{$uri->path} = $req->{database_type}->create($self->databases_path . $uri->path);
		$self->config->{databases}{$uri->path} = {
			database_type => $req->{database_type},
		};

		$self->store_config;

		return Carbon::Limestone::Response->new(status => 'success');

	} elsif ($req->{method} eq 'delete') {
		return Carbon::Limestone::Response->new(status => 'error', error => 'database already exists')
				unless exists $self->databases->{$uri->path};
		return Carbon::Limestone::Response->new(status => 'error', error => 'incorrect database type')
				unless exists $req->{database_type} and $self->databases->{$uri->path}->database_type;

		my $database = $self->databases->{$uri->path};
		$database->lock_all_edits;
		$database->delete;
		delete $self->databases->{$uri->path};
		delete $self->config->{databases}{$uri->path};

		$self->store_config;

		return Carbon::Limestone::Response->new(status => 'success');

	} elsif ($req->{method} eq 'query') {
		return Carbon::Limestone::Response->new(status => 'error', error => 'database already exists')
				unless exists $self->databases->{$uri->path};
		return Carbon::Limestone::Response->new(status => 'error', error => 'incorrect database type')
				unless exists $req->{database_type} and $self->databases->{$uri->path}->database_type;

		return $self->databases->{$uri->path}->execute_query($req);

	} elsif ($req->{method} eq 'list') {
		return Carbon::Limestone::Response->new(status => 'success',
				data => { map $_ => $self->databases->{$_}->database_type, sort keys %{$self->databases} });

	} else {

		return Carbon::Limestone::Response->new(status => 'error', error => 'invalid method');
	}
}





1;
