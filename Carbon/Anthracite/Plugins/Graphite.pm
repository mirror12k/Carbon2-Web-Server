package Carbon::Anthracite::Plugins::Graphite;
use parent 'Carbon::Anthracite::Plugin';
use strict;
use warnings;

use feature 'say';


use Carbon::Graphite;



# a plugin for hooking necessary compiler functions and to provide a runtime interface to the Graphite engine



sub new {
	my $class = shift;
	my %args = @_;
	my $self = $class->SUPER::new;

	$self->engine($args{engine} // Carbon::Graphite->new);

	return $self
}



sub engine { @_ > 1 ? $_[0]{anthracite_plugin_graphite__engine} = $_[1] : $_[0]{anthracite_plugin_graphite__engine} }





# api methods

sub get_template {
	my ($self, $name) = @_;
	return $self->engine->template($name);
}

sub set_template {
	my ($self, $name, $template) = @_;
	# say "created template '$name'";
	$self->engine->template($name => $template);
}

sub render_template {
	my ($self, $name, $arg) = @_;

	my $template;
	if (ref $name) { # if the second argument is a template object
		$template = $name;
	} else { # otherwise it's a name for retrieving a template
		$template = $self->engine->template($name);
	}
	die "attempt to render missing template: '$name'" unless defined $template;
	return $template->execute($self, $arg)
}


sub get_helper {
	my ($self, $name) = @_;
	return $self->engine->helper($name)
}

sub set_helper {
	my ($self, $name, $helper) = @_;
	$self->engine->helper($name => $helper);
}



# low-level api methods

sub push_namespace {
	my ($self, $namespace) = @_;
	$self->engine->push_namespace($namespace);
}
sub pop_namespace {
	my ($self) = @_;
	$self->engine->pop_namespace;
}


sub condition_else {
	my ($self, $value) = @_;
	return @_ > 1 ? $self->engine->condition_else($value) : $self->engine->condition_else
}




# overridden plugin methods


# capture any graphite directive tokens for the engine to compile
sub compile_token {
	my ($self, $token) = @_;
	my ($token_type, $raw, $tag_type, $tag_data) = @$token;
	if ($token_type eq 'directive' and $tag_type eq 'graphite') {
		return $self->compile_graphite($tag_data)
	} else {
		return '', $token
	}
}



sub compile_graphite {
	my ($self, $text) = @_;
	return $self->engine->compiler->compile_graphite_directive($text);
}



# add our runtime code for loading the api
sub code_header {
	my ($self, $data) = @_;
	return
'
our $graphite = $runtime->{anthracite_plugin_graphite__interface};
'
}

# parasitize the runtime object to transport our api
sub create_runtime {
	my ($self, $runtime) = @_;
	$runtime->{anthracite_plugin_graphite__interface} = $self;
	return $runtime
}




1;
