package Carbon::Anthracite;
use parent 'Carbon::Router';
use strict;
use warnings;

use feature 'say';
use File::Slurper 'read_binary';

use Carbon::HTTP::MIME;
use Carbon::HTTP::Response;

use Carbon::Anthracite::Runtime;
use Carbon::Anthracite::Compiler;



sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new(%args);

	# $self->debug($args{debug} // 0);
	$self->plugins([]);

	for my $plugin (@{$args{plugins} // []}) {
		$self->add_plugin($plugin);
	}

	return $self
}

# sub warn {
# 	my ($self, $level, $message) = @_;
# 	if ($self->{debug} and $self->{debug} <= $level) {
# 		CORE::warn "[". (caller)[0] ."]: $message\n";
# 	}
# }



# sub debug { @_ > 1 ? $_[0]{debug} = $_[1] : $_[0]{debug} }
# sub parser { @_ > 1 ? $_[0]{carbon_anthracite__parser} = $_[1] : $_[0]{carbon_anthracite__parser} }
sub plugins { @_ > 1 ? $_[0]{carbon_anthracite__plugins} = $_[1] : $_[0]{carbon_anthracite__plugins} }



sub add_plugin {
	my ($self, $plugin) = @_;
	push @{$self->plugins}, $plugin;
	$plugin->initialize($self);
}

sub init_thread {
	my ($self) = @_;

	for my $plugin (@{$self->plugins}) {
		$plugin->init_thread;
	}
}



sub execute_dynamic_file {
	my ($self, $file, $req) = @_;
	my $runtime = Carbon::Anthracite::Runtime->new($self, $req);
	$runtime->execute($self->compile_dynamic_file($file));
	return $runtime->produce_response
}

sub include_dynamic_file {
	my ($self, $runtime, $file) = @_;
	$runtime->execute($self->compile_dynamic_file($file));
}

sub compile_dynamic_file {
	my ($self, $file) = @_;
	return Carbon::Anthracite::Compiler->new($self->plugins)->compile($file);
}

sub route_dynamic {
	my ($self, $path, $directory, %opts) = @_;

	my $suffix = $opts{suffix} // ''; # allows a file suffix to be appended
	my $default_file = $opts{default_file} // 'index.am'; # allows different default files to be named
	my $executable = defined $opts{executable} ? qr/$opts{executable}\Z/ : qr/\.am\Z/; # specifies the types of files/file-extensions that can be executed

	return $self->route(qr/$path.*/ => sub {
		my ($self, $req) = @_;

		my $loc = $req->uri->path;
		$loc =~ s/\A$path//;
		$loc = join '/', grep $_ !~ /\A\./, grep $_ ne '', split '/', $loc;
		$loc = "$directory/$loc";

		say "debug loc: $loc";
		my $res;
		if (-e -f "$loc$suffix") { # if the file exists
			if ("$loc$suffix" =~ $executable) { # if it's executable
				$res = $self->execute_dynamic_file("$loc$suffix", $req);
			} else {
				$res = $self->load_static_file("$loc$suffix", $req);
			}
		} elsif (-d $loc and -e -f "$loc/$default_file$suffix") { # if it's a directory, but we have an index file
			if ("$loc/$default_file$suffix" =~ $executable) { # if it's executable
				$res = $self->execute_dynamic_file("$loc/$default_file$suffix", $req);
			} else {
				$res = $self->load_static_file("$loc/$default_file$suffix", $req);
			}

		} elsif (-d $loc) { # if it's a directory
			$res = Carbon::HTTP::Response->new('403');
			$res->content("Forbidden");
			$res->header('content-type' => 'text/plain');
			$res->header('content-length' => length $res->content);

		} else { # otherwise it's not found
			$res = Carbon::HTTP::Response->new('404');
			$res->content("Not Found");
			$res->header('content-type' => 'text/plain');
			$res->header('content-length' => length $res->content);
		}

		return $res
	}, %opts);
}

1;
