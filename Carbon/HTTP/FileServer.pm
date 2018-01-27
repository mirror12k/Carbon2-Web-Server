package Carbon::HTTP::FileServer;
use parent 'Carbon::Router';
use strict;
use warnings;

use feature 'say';
# use File::Slurper 'read_binary';

use Carbon::HTTP::MIME;
use Carbon::HTTP::Response;



sub route_directory {
	my ($self, $path, $directory, %opts) = @_;
	
	return $self->route(qr/$path.*/ => sub {
		my ($self, $req, $res) = @_;

		# some basic munging and filtering of the path
		my $loc = $req->uri->path;
		$loc =~ s/\A$path//;
		$loc = join '/', grep $_ !~ /\.\./, grep $_ ne '', split '/', $loc;
		$loc = "$directory/$loc";

		if (-e $loc) { # if the location exists
			if (-f _) { # if it's a file
				$res = $self->load_static_file($loc);
			} elsif (-d _) { # if it's a directory
				if (defined $opts{default_file} and -e -f "$loc/$opts{default_file}") {
					$res = $self->load_static_file("$loc/$opts{default_file}");
				} elsif (not $opts{forbid_directories}) {
					# say "debug: $opts->{forbid_directories}";
					$res = $self->load_directory_list($loc, $req->uri->path);
				} else {
					$res //= Carbon::HTTP::Response->new;
					$res->code('403');
					$res->content('Forbidden');
					$res->header('content-type' => 'text/plain');
					$res->header('content-length' => length $res->content);
				}
			} else { # we forbid anything else
				$res //= Carbon::HTTP::Response->new;
				$res->code('403');
				$res->content('Forbidden');
				$res->header('content-type' => 'text/plain');
				$res->header('content-length' => length $res->content);
			}
		} else { # if the location doesn't exist
			$res //= Carbon::HTTP::Response->new;
			$res->code('404');
			$res->content("Not Found: $loc");
			$res->header('content-type' => 'text/plain');
			$res->header('content-length' => length $res->content);
		}

		return $res
	}, %opts);
}



sub load_static_file {
	my ($self, $filepath) = @_;

	my $res = Carbon::HTTP::Response->new('200');
	# my $data = read_binary($filepath);
	# $res->content($data);
	$res->content({ filepath => $filepath });
	# $res->header('content-length' => length $res->content);
	$res->header('content-length' => -s $filepath);
	$res->header('content-type' => $self->get_content_type($filepath));

	return $res
}

sub load_directory_list {
	my ($self, $dirpath, $display_path) = @_;

	my $res = Carbon::HTTP::Response->new('200');
	$res->header('content-type' => 'text/html');

	opendir my ($dir), $dirpath;
	my @list = sort readdir $dir;
	closedir $dir;

	$display_path = $display_path // $dirpath;
	my $data = "<!doctype html><html><body><h1>Index of $display_path</h1>" .
		(join '', map "<a href='./" . (-d "$dirpath/$_" ? "$_/" : "$_") . "'>" . (-d _ ? "$_/" : "$_") . "</a><br>", @list) .
		"</body></html>\n";
	$res->content($data);
	$res->header('content-length' => length $res->content);

	return $res
}

sub get_content_type {
	my ($self, $filepath) = @_;

	my $content_type = Carbon::HTTP::MIME::get_mime_type($filepath);
	return $content_type // 'text/plain'
}

1;
