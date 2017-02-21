package Carbon::Graphite;
use strict;
use warnings;

use feature 'say';


# graphite engine

use Carbon::Graphite::Compiler;
use Carbon::Graphite::Helper;
use Carbon::Graphite::Template;


sub new {
	my $class = shift;
	my %args = @_;
	my $self = bless {}, $class;

	$self->templates({});
	$self->helpers({
		template => Carbon::Graphite::Helper->new(\&helper_template),
		foreach => Carbon::Graphite::Helper->new(\&helper_foreach),
		if => Carbon::Graphite::Helper->new(\&helper_if),
		elsif => Carbon::Graphite::Helper->new(\&helper_elsif),
		else => Carbon::Graphite::Helper->new(\&helper_else),
		with => Carbon::Graphite::Helper->new(\&helper_with),
		namespace => Carbon::Graphite::Helper->new(\&helper_namespace),
	});

	$self->compiler(Carbon::Graphite::Compiler->new($self));
	$self->condition_else(0);
	$self->namespace_stack([]);

	return $self
}



sub templates { @_ > 1 ? $_[0]{carbon_graphite__templates} = $_[1] : $_[0]{carbon_graphite__templates} }
sub helpers { @_ > 1 ? $_[0]{carbon_graphite__helpers} = $_[1] : $_[0]{carbon_graphite__helpers} }
sub compiler { @_ > 1 ? $_[0]{carbon_graphite__compiler} = $_[1] : $_[0]{carbon_graphite__compiler} }
sub condition_else { @_ > 1 ? $_[0]{carbon_graphite__condition_else} = $_[1] : $_[0]{carbon_graphite__condition_else} }
sub namespace_stack { @_ > 1 ? $_[0]{carbon_graphite__namespace_stack} = $_[1] : $_[0]{carbon_graphite__namespace_stack} }


# api functions

sub current_namespace {
	my ($self) = @_;
	if (@{$self->namespace_stack}) {
		return join '::', @{$self->namespace_stack}
	} else {
		return
	}
}

sub push_namespace {
	my ($self, $namespace) = @_;
	push @{$self->namespace_stack}, $namespace;
}
sub pop_namespace {
	my ($self) = @_;
	pop @{$self->namespace_stack};
}

sub template {
	my ($self, $name, $value) = @_;

	my $namespace = $self->current_namespace;
	$name = "${namespace}::$name" if defined $namespace;

	# say "accessing template '$name'";

	if (@_ > 2) {
		return $self->templates->{$name} = $value;
	} else {
		return $self->templates->{$name}
	}
}

sub helper {
	my ($self, $name, $value) = @_;
	if (@_ > 2) {
		return $self->helpers->{$name} = $value;
	} else {
		return $self->helpers->{$name}
	}
}



# graphite helper functions

sub helper_template {
	my ($helper, $engine, $text) = @_;

	$text =~ s/\A\s*($Carbon::Graphite::Compiler::name_regex(?:::$Carbon::Graphite::Compiler::name_regex)*)\s+//s
		or die '"template" helper requires a text name at start';
	my $name = $1;

	my $code =
"
;\$graphite->set_template('$name' => Carbon::Graphite::Template->new( sub {
my (\$self, \$graphite, \$arg) = \@_;
my \$output = '';
";
	$code .= $engine->compile_graphite ($text);
	$code .=
'
;return $output
}));
';
	return $code
}


sub helper_foreach {
	my ($helper, $engine, $text) = @_;
	$text =~ s/\A\s*($Carbon::Graphite::Compiler::variable_regex)\b//s or die '"foreach" helper requires variable name at start';
	my $name = $1;
	$name = $engine->compile_inc_val($name);
	my $code =
"
;foreach my \$arg (\@{$name}) {
";
	$code .= $engine->compile_graphite ($text);
	$code .= "\n}\n";

	return $code
}


sub helper_if {
	my ($helper, $engine, $text) = @_;
	$text =~ s/\A\s*\(([^)]*)\)//s or die '"if" helper requires a condition at start';
	my $condition = $1;

	$condition =~ s/(\$[a-zA-Z0-9_]+)\b/$engine->compile_inc_val($1)/e;
	my $code =
"
;\$graphite->condition_else(1);
if ($condition) {
";

	$code .= $engine->compile_graphite ($text);
	$code .= 
"
;\$graphite->condition_else(0);
}
";

	return $code
}

sub helper_elsif {
	my ($helper, $engine, $text) = @_;
	$text =~ s/\A\s*\(([^)]*)\)//s or die '"elsif" helper requires a condition at start';
	my $condition = $1;

	$condition =~ s/(\$[a-zA-Z0-9_]+)\b/$engine->compile_inc_val($1)/e;
	my $code =
"
;if (\$graphite->condition_else and ($condition)) {
";

	$code .= $engine->compile_graphite ($text);
	$code .= 
"
;\$graphite->condition_else(0);
}
";

	return $code
}

sub helper_else {
	my ($helper, $engine, $text) = @_;

	my $code =
"
;if (\$graphite->condition_else) {
";

	$code .= $engine->compile_graphite ($text);
	$code .= 
"
}
";

	return $code
}


sub helper_with {
	my ($helper, $engine, $text) = @_;
	$text =~ s/\A\s*(\$[a-zA-Z0-9_]+)\b//s or die '"with" helper requires variable name at start';
	my $name = $1;
	$name = $engine->compile_inc_val($name);
	my $code =
"
;do {
my \$arg = $name;
";
	$code .= $engine->compile_graphite ($text);
	$code .= "\n}\n";

	return $code
}


sub helper_namespace {
	my ($helper, $engine, $text) = @_;
	$text =~ s/\A\s*([a-zA-Z0-9_]+(?:::[a-zA-Z0-9_]+)*)\b//s or die '"namespace" helper requires namespace name at start';
	my $name = $1;
	my $code =
"
;\$graphite->push_namespace('$name');
";
	$code .= $engine->compile_graphite ($text);
	$code .= 
"
;\$graphite->pop_namespace;
";

	return $code
}

1;

