package Carbon::Graphite::Compiler;
use strict;
use warnings;

use feature 'say';

use Carbon::Graphite::Parser;



# a text parser for parsing out graphite helper calls


sub new {
	my ($class, $engine) = @_;
	my $self = bless {}, $class;

	$self->{engine} = $engine;

	return $self
}

sub compile_graphite_directive {
	my ($self, $block) = @_;
	my $code = $self->code_header;

	$code .= $self->compile_graphite($block);

	$code .= $self->code_tail;
	return $code
}

sub compile_graphite {
	my ($self, $initial_text) = @_;

	my $parser = Carbon::Graphite::Parser->new($initial_text);

	my @helper_stack;
	my $code = '';

	while (my ($type, $text, $raw) = $parser->get_token) {
		if ($type eq 'helper') {
			my $block = $parser->get_until_end_helper;
			if (defined $self->{engine}->helper($text)) {
				$code .= $self->{engine}->helper($text)->execute($self, $block);
			} else {
				die "attempt to invoke unknown helper '$text'";
			}
		} elsif ($type eq 'end_helper') {
			die "out of order end helper";
		} elsif ($type eq 'comment') {
			# do nothing for comments
			# perhaps if a comment is followed by a template declaration, it should be marked as the documentation for said template?
		} elsif ($type eq 'text') {
			$code .= $self->compile_text($text);
		} else {
			die "unknown token type '$type'";
		}
	}
	return $code
}



sub code_header {
	return '
;do { # graphite code block
my $output = "";
'
}

sub code_tail {
	return '
;echo $output;
}; # end of graphite code
'
}

our $name_regex = qr/[a-zA-Z_][a-zA-Z0-9_]*/;
our $variable_regex = qr/\$$name_regex/;
our $template_regex = qr/\@$name_regex(?:::$name_regex)*/;
our $value_regex = qr/
		$variable_regex| # variable
		$template_regex| # template
		-?\d+(\.\d+)?| # numeric value
		'[^']*'| # string
		"[^"]*" # string
		/sx;
# because of the recursive nature of it, it screws up any numbered capture groups
# use with caution
our $graphite_extended_value_regex = qr/
	(?<extended>
	$value_regex|
	\[\s*(?:(?&extended)(?:\s*,\s*(?&extended))*\s*(?:,\s*)?)?\]|
	\{\s*(?:$name_regex\s*=>\s*(?&extended)(?:\s*,\s*$name_regex\s*=>\s*(?&extended))*\s*(?:,\s*)?)?\}
	)
/sx;

sub compile_text {
	my ($self, $text) = @_;

	return '' if $text =~ /\A\s*\Z/m;

	$text =~ s/\A\s+/ /m;
	$text =~ s/\A\s+</</m;
	$text =~ s/\s+\Z/ /m;
	$text =~ s/>\s+\Z/>/m;

	my $code = ";\n";

	while ($text =~ /\G
			(?<variable>$variable_regex)|
			(?<template>\@$variable_regex|$template_regex)(?:->(?<template_arg>$graphite_extended_value_regex))?|
			(?<text>.*?(?:(?=[\$\@])|\Z))
			/sgx) {
		my ($var, $inc, $inc_val, $html) = @+{qw/ variable template template_arg text /};
		if (defined $var) {
			$code .= "\n;\$output .= ". $self->compile_inc_val($var) .";\n";
		} elsif (defined $inc) {
			$inc = substr $inc, 1; # chop off the @
			if ($inc =~ /\A\$/) {
				$inc = $self->compile_inc_val($inc);
			} else {
				$inc = "'$inc'";
			}
			if (defined $inc_val) {
				my $inc_code = $self->compile_inc_extended_val($inc_val);
				$code .= "\n;\$output .= \$graphite->render_template($inc => $inc_code);\n";
			} else {
				$code .= "\n;\$output .= \$graphite->render_template($inc);\n";
			}
		} else {
			$html =~ s/\A\s+/ /m;
			$html =~ s/\s+\Z/ /m;
			$html =~ s#\\#\\\\#g;
			$html =~ s#'#\\'#g;
			next if $html =~ /\A\s*\Z/m;
			$code .= "\n;\$output .= '$html';\n";
		}
	}
	return $code
}

sub compile_inc_val {
	my ($self, $val) = @_;
	if ($val =~ /\A($variable_regex)\Z/) {
		my $name = substr $1, 1;
		if ($name ne '_') {
			return "\$arg->{$name}";
		} else {
			return '$arg';
		}
	} elsif ($val =~ /\A($template_regex)\Z/) {
		return "\$graphite->get_template('". substr($1, 1) ."')";
	} elsif ($val =~ /\A\d+\Z/) {
		return $val;
	} elsif ($val =~ /\A'[^']*'\Z/) {
		return $val;
	} elsif ($val =~ /\A"([^"]*)"\Z/) {
		return "'$1'";
	} else {
		die "unknown value to compile: '$val'";
	}
}

sub compile_inc_extended_val {
	my ($self, $val) = @_;
	if ($val =~ /\A($variable_regex)\Z/) {
		my $name = substr $1, 1;
		if ($name ne '_') {
			return "\$arg->{$name}"
		} else {
			return '$arg'
		}
	} elsif ($val =~ /\A($template_regex)\Z/) {
		return "\$graphite->get_template('". substr($1, 1) ."')"
	} elsif ($val =~ /\A-?\d+(\.\d+)?\Z/) {
		return $val
	} elsif ($val =~ /\A'[^']*'\Z/) {
		return $val
	} elsif ($val =~ /\A"([^"]*)"\Z/) {
		return "'$1'"
	} elsif ($val =~ /\A\[/) {
		return $self->compile_inc_list($val)
	} elsif ($val =~ /\A\{/) {
		return $self->compile_inc_hash($val)
	} else {
		die "unknown value to compile: '$val'";
	}
}

sub compile_inc_list {
	my ($self, $text) = @_;

	$text =~ s/\A\[(.*)\]\Z/$1/s or die "not an array: '$text'";

	my $code = '[';

	while ($text =~ /\G\s*(?<val>$graphite_extended_value_regex)\s*(?<cont>,\s*)?/sg) {
		my ($val, $cont) = @+{qw/ val cont /};
		$code .= $self->compile_inc_extended_val($val) . ', ';
		last unless defined $cont;
	}

	$code .= ']';

	return $code
}

sub compile_inc_hash {
	my ($self, $text) = @_;

	$text =~ s/\A\{(.*)\}\Z/$1/s or die "not a hash: '$text'";

	my $code = '{';

	while ($text =~ /\G\s*(?<key>$name_regex)\s*=>\s*(?<val>$graphite_extended_value_regex)\s*(?<cont>,\s*)?/sg) {
		my ($key, $val, $cont) = @+{qw/ key val cont /};
		$code .= "'$key' => " . $self->compile_inc_extended_val($val) . ', ';
		last unless defined $cont;
	}

	$code .= '}';
	return $code
}



1;
