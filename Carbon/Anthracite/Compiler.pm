package Carbon::Anthracite::Compiler;
use strict;
use warnings;

use feature 'say';

use File::Slurper 'read_binary';

use Carbon::Anthracite::CompiledFile;



# a simple html parser which parses out tags, text, and directives


sub new {
	my ($class, $plugins) = @_;
	my $self = bless {}, $class;
	$self->plugins($plugins);

	return $self
}

sub plugins { @_ > 1 ? $_[0]{carbon_anthracite_compiler__plugins} = $_[1] : $_[0]{carbon_anthracite_compiler__plugins} }

sub compile {
	my ($self, $file) = @_;

	# warn "compiling '$file'";

	my $data = Carbon::Anthracite::CompiledFile->new;
	$data->filepath($file);

	$self->{text} = read_binary($file);
	$self->{carbon_anthracite_compiler__echo_accumulator} = '';

	my $code = $self->code_header($data);
	for my $plugin (@{$self->plugins}) {
		$code .= $plugin->code_header($data);
	}

	# say "code header: $code";
	TOKEN: while (my @token = $self->get_token) {
		# say "debug got token: [ @token ]";
		# first let the plugins view the token
		for my $plugin (@{$self->plugins}) {
			my ($new_code, $new_token) = $plugin->compile_token([@token]);
			if ($new_code ne '') {
				$code .= $self->get_echo_code;
				$code .= $new_code; # append any code
			}
			next TOKEN unless defined $new_token; # if it didn't return a token, we should stop propagating it
			@token = @$new_token;
		}
		$code .= $self->compile_token(@token);
	}

	for my $plugin (@{$self->plugins}) {
		$code .= $plugin->code_tail($data);
	}
	$code .= $self->code_tail($data);

	# say "compiled code: $code";

	my $compiled = eval $code;
	if ($@) {
		CORE::die "compilation failed: $@";
	} else {
		$data->code($compiled);
	}

	return $data
}

# parses text and returns the next token in text or undef if parsing is done
# token is a list describing the token, the first value being the type of token
sub get_token {
	my ($self) = @_;

	# don't restart parsing after we've already completed it
	return if $self->{complete};

	# get a token from text
	while ($self->{text} =~
			m/\G
				(<([!\/]?[a-zA-Z]+\b)(.*?)>)| # match a start tag, end tag, or comment
				(<\?([a-zA-Z]+)(.*?)(?:\?>|\Z(?!\s)))| # match a directive
											# this is a fix for some inexplicable behavior where the 
											# \Z will match on the newline before the end of the string
				(.+?)(?:(?=<)|\Z) # match regular text
			/smxg) {
		my ($tag, $tag_type, $tag_data, $directive, $directive_type, $directive_data, $text) = ($1, $2, $3, $4, $5, $6, $7);

		# parse the result
		if (defined $tag) {
			return tag => $tag, $tag_type, $tag_data
		} elsif (defined $directive) {
			return directive => $directive, $directive_type, $directive_data
		} else {
			return text => $text
		}
	}
	# since the regex stopped matching, we have completed the search and should not return
	$self->{complete} = 1;

	return
}




sub compile_token {
	my ($self, $token_type, $raw, $tag_type, $tag_data) = @_;

	if ($token_type eq 'tag' or $token_type eq 'text') {
		$self->{carbon_anthracite_compiler__echo_accumulator} .= $raw;
		return '';
	} elsif ($token_type eq 'directive') {
		if ($tag_type eq 'perl') {
			my $code = '';
			$code .= $self->get_echo_code;
			$code .= "$tag_data\n";
		} else {
			die "unknown directive type: $tag_type";
		}
	} else {
		die "unknown token type: $token_type";
	}
}

sub code_header {
	my ($self, $data) = @_;
	return '
sub {
# this is necessary to prevent redefinition of symbols			
package Carbon::Anthracite::Dynamic::'. ($data->filepath =~ s/[^a-zA-Z_]/_/gr) .';
our ($runtime) = @_;

use subs qw/ echo /;
local *echo = sub { $runtime->echo(@_) };
'
}

sub code_tail {
	my ($self) = @_;
	my $code = '';
	$code .= $self->get_echo_code;
	$code .= "\n}\n";
	return $code
}


sub get_echo_code {
	my ($self) = @_;
	my $code = '';
	if ($self->{carbon_anthracite_compiler__echo_accumulator} ne '') {
		$code = $self->code_wrap_text($self->{carbon_anthracite_compiler__echo_accumulator});
		$self->{carbon_anthracite_compiler__echo_accumulator} = '';
	}
	return $code
}

sub code_wrap_text {
	my ($self, $text) = @_;
	$text =~ s/\\/\\\\/g;
	$text =~ s/'/\\'/g;
	return "\n;echo('$text');\n"
}


1;

