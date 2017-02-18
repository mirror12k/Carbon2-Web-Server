package Carbon::HTTP::CGIServer;
use parent 'Carbon::Router';
use strict;
use warnings;

use feature 'say';

use IPC::Open2;

use Carbon::HTTP::Response;





sub new {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new(%args);

	$self->command_line($args{command_line} // 'php5-cgi');

	return $self
}

sub command_line { @_ > 1 ? $_[0]{carbon_http_cgiserver__command_line} = $_[1] : $_[0]{carbon_http_cgiserver__command_line} }



sub route_cgi {
	my ($self, $path, $directory, %opts) = @_;

	my $suffix = $opts{suffix} // ''; # allows a file suffix to be appended
	my $default_file = $opts{default_file} // 'index'; # allows different default files to be named

	return $self->route(qr/$path.*/ => sub {
		my ($self, $req, $res) = @_;

		my $loc = $req->uri->path;
		$loc =~ s/\A$path//;
		$loc = join '/', grep $_ !~ /\A\./, grep $_ ne '', split '/', $loc;
		$loc = "$directory/$loc";

		say "debug loc: $loc";

		if (-e -f "$loc$suffix") { # if the file exists
			$res = $self->execute_cgi("$loc$suffix", $req);
		} elsif (-d $loc and -e -f "$loc/$default_file$suffix") { # if it's a directory, but we have an index file
			$res = $self->execute_cgi("$loc/$default_file$suffix", $req);
		} else { # otherwise it's not found
			$res //= Carbon::HTTP::Response->new;
			$res->code('404');
			$res->content("Not Found");
			$res->header('content-type' => 'text/plain');
		}
		$res->header('content-length' => length $res->content);

		return $res
	}, %opts);
}

sub execute_cgi {
	my ($self, $filepath, $req) = @_;

	my $cmd = $self->command_line;

	my %cgi_env = (
		GATEWAY_INTERFACE => 'CGI/1.1',
		PATH_INFO => $req->uri->path // '/',
		PATH_TRANSLATED => $req->uri->path // '/', # pretend it's the same thing
		QUERY_STRING => $req->uri->query // '',
		REMOTE_ADDR => '127.0.0.1',
		# REMOTE_HOST =>
		REQUEST_METHOD => $req->method,
		SCRIPT_NAME => $filepath,
		# php cgi doesn't seem to care for SCRIPT_NAME, instead it wants SCRIPT_FILENAME
		SCRIPT_FILENAME => $filepath,
		SERVER_NAME => '127.0.0.1',
		SERVER_PORT => '22222',
		SERVER_PROTOCOL => $req->protocol,
		SERVER_SOFTWARE => 'Carbon::CGI/0.01',
		# required otherwise php cgi refuses to work, i have no clue what it does, doesn't seem to be documented anywhere
		REDIRECT_STATUS => '',
	);
	for my $key (keys %{$req->headers}) {
		$cgi_env{'HTTP_' . uc ($key =~ s/-/_/gr)} = join ', ', $req->header($key);
	}

	if (defined $req->header('content-length')) {
		$cgi_env{CONTENT_LENGTH} = int $req->header('content-length');
	}
	if (defined $req->header('content-type')) {
		$cgi_env{CONTENT_TYPE} = $req->header('content-type');
	}

	# while (my ($k, $v) = each %cgi_env) {
	# 	say "env: $k => $v";
	# }
	my $envcmd  = 'env -i ' . join ' ', map "'$_=$cgi_env{$_}'", keys %cgi_env;

	# open the process
	my $pid = open2(my $out, my $in, "$envcmd $cmd") or die "failed to start cgi process";
	$in->print($req->content) if defined $req->content; # give it the content on stdin

	waitpid($pid, 0); # wait for it to finish

	my $output;
	do {
		local $/;
		$output = <$out>; # get all input
	};
	close $in;
	close $out;

	# process output
	# say "got output: [$output]";
	if ($output =~ /\AStatus:\s*/) {
		$output =~ s/\AStatus:\s*/HTTP\/1.1 /;
	} elsif ($output =~ /\ALocation:\s*/) {
		$output = "HTTP/1.1 303 See Other\r\n$output";
	} else {
		$output = "HTTP/1.1 200 OK\r\n$output";
	}
	# say "made: [$output]";
	# return it as a response
	return Carbon::HTTP::Response->parse($output);
}




1;
