package MyAwesomePlugin;
use parent 'Carbon::Anthracite::Plugin';
use strict;
use warnings;

use feature 'say';



# capture any text tokens and compile them manually
sub compile_token {
	my ($self, $token) = @_;
	my ($token_type, $text) = @$token;
	if ($token_type eq 'text') {
		return $self->compile_text_sub($text)
	} else {
		return '', $token
	}
}

sub compile_text_sub {
	my ($self, $text) = @_;

	my $code = '';
	while ($text =~ /\G(\{\{(.*)\}\}|(.+?)(?:\Z|(?=\{\{)))/sg) {
		if (defined $2) {
			$code .= ";echo (\$runtime->get_arg('$2') // '');\n";
		} else {
			$code .= ";echo '$3';\n";
		}
	}

	return $code
}

1;
