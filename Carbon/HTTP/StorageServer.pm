package Carbon::HTTP::StorageServer;
use parent 'Carbon::Router';
use strict;
use warnings;

use feature 'say';
use File::Slurper qw/ read_binary write_binary /;
use File::Path qw/ make_path remove_tree /;

use Carbon::HTTP::MIME;
use Carbon::HTTP::Response;

use JSON;



# a generic RESTful file storage server

sub route_storage {
	my ($self, $path, $directory, %opts) = @_;

	my $permissions = defined $opts{permission}
			? $self->load_permissions($opts{permission})
			: { anon => { read => 1, write => 1 } };

	return $self->route(qr/$path.*/ => sub {
		my ($self, $req) = @_;

		# some basic munging and filtering of the path
		my $loc = $req->uri->path;
		$loc =~ s/\A$path//;
		$loc = join '/', grep $_ !~ /\.\./, grep $_ ne '', split '/', $loc;
		$loc = "$directory/$loc";

		my $user = $req->uri->query_form->{user} // 'anon';

		my $res;
		if ($req->method eq 'GET') {
			if (exists $permissions->{$user} and $permissions->{$user}{read}) {
				$res = $self->get_file($loc);
			} else {
				$res = Carbon::HTTP::Response->new('403', 'Forbidden');
				$res->content('Forbidden');
				$res->header('content-length' => length $res->content);
			}
		} elsif ($req->method eq 'PUT') {
			if (exists $permissions->{$user} and $permissions->{$user}{write}) {
				$res = $self->put_file($loc, $req->content);
			} else {
				$res = Carbon::HTTP::Response->new('403', 'Forbidden');
				$res->content('Forbidden');
				$res->header('content-length' => length $res->content);
			}
		} elsif ($req->method eq 'DELETE') {
			if (exists $permissions->{$user} and $permissions->{$user}{write}) {
				$res = $self->delete_file($loc);
			} else {
				$res = Carbon::HTTP::Response->new('403', 'Forbidden');
				$res->content('Forbidden');
				$res->header('content-length' => length $res->content);
			}
		} else {
			$res = Carbon::HTTP::Response->new('400', 'Bad Request');
			$res->content('Bad Request');
			$res->header('content-length' => length $res->content);
		}

		return $res
	});
}

sub load_permissions {
	my ($self, $filepath) = @_;
	die "missing permissions file '$filepath'" unless -e -f $filepath;
	return decode_json read_binary ($filepath)
}

sub get_file {
	my ($self, $filepath) = @_;

	my $res;
	if (-e -f $filepath) {
		$res = Carbon::HTTP::Response->new('200');
		my $data = read_binary($filepath);
		$res->content($data);
		$res->header('content-length' => length $res->content);
		$res->header('content-type' => $self->get_content_type($filepath));
	} else {
		$res = Carbon::HTTP::Response->new('404', 'Not Found');
		$res->header('content-length' => 0);
	}

	return $res
}

sub put_file {
	my ($self, $filepath, $data) = @_;

	my $directory = $filepath =~ s/\A(.*)\/[^\/]+\Z/$1/rs;
	unless (-e $directory) {
		make_path($directory);
	}

	unless (-e -d $directory) {
		my $res = Carbon::HTTP::Response->new('403', 'Not A Directory');
		$res->header('content-length' => 0);
		return $res
	}

	write_binary($filepath, $data);
	
	my $res = Carbon::HTTP::Response->new('200');
	$res->header('content-length' => 0);

	return $res
}

sub delete_file {
	my ($self, $filepath) = @_;

	my $res;
	if (-e -f $filepath) {
		unlink $filepath;
		$res = Carbon::HTTP::Response->new('200', 'OK');
		$res->header('content-length' => 0);
	} elsif (-e -d $filepath) {
		remove_tree($filepath);
		$res = Carbon::HTTP::Response->new('200', 'OK');
		$res->header('content-length' => 0);
	} else {
		$res = Carbon::HTTP::Response->new('404', 'Not Found');
		$res->header('content-length' => 0);
	}

	return $res
}

sub get_content_type {
	my ($self, $filepath) = @_;

	my $content_type = Carbon::HTTP::MIME::get_mime_type($filepath);
	return $content_type // 'text/plain'
}

1;
