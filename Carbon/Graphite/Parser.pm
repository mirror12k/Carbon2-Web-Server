package Carbon::Graphite::Parser;
use strict;
use warnings;

use feature 'say';



# a text parser for parsing out graphite helper calls


sub new {
	my ($class, $text) = @_;
	my $self = bless {}, $class;

	$self->set_text($text);

	return $self
}

sub set_text {
	my ($self, $text) = @_;
	$self->{text} = $text;
	$self->{complete} = 0;
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
				((\#([a-zA-Z0-9_]+(?:::[a-zA-Z0-9_]+)*)\b)|
				(\#\/)|
				(\#\#\#(.*?)(?:\#\#\#|\Z))|
				(.+?)(?:(?=\#)|\Z)) # match regular text
			/sxg) {
		my ($raw, $helper, $helper_name, $end_helper, $comment, $comment_text, $text) = ($1, $2, $3, $4, $5, $6, $7);
		# say "debug:  $helper, $helper_name, $end_helper, $text";
		if (defined $helper) {
			return helper => $helper_name, $raw
		} elsif (defined $comment) {
			return comment => $comment_text, $raw
		} elsif (defined $end_helper) {
			return end_helper => undef, $raw
		} else {
			return text => $text, $raw
		}
	}
	# since the regex stopped matching, we have completed the search and should not return
	$self->{complete} = 1;

	return
}


# returns all the text inside the last helper token until the helper's associated end_helper token
sub get_until_end_helper {
	my ($self) = @_;
	my $text = '';
	my $nesting = 1;
	while (my ($type, undef, $raw) = $self->get_token) {
		if ($type eq 'helper') {
			$nesting++;
		} elsif ($type eq 'end_helper') {
			$nesting--;
			if ($nesting == 0) {
				last
			}
		}
		$text .= $raw;
	}
	if ($nesting > 0) {
		die "unclosed helper invokation";
	}
	return $text
}

1;


