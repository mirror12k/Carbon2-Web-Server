package Carbon::Anthracite::Runtime;
use strict;
use warnings;

use feature 'say';

use Carbon::HTTP::Response;
use Carbon::HTTP::Util;


sub new {
	my ($class, $parent, $request) = @_;
	my $self = bless {}, $class;

	$self->{carbon_anthracite_runtime__output} = '';
	open my $echo_handle, '>>', \($self->{carbon_anthracite_runtime__output});
	$self->{carbon_anthracite_runtime__echo_handle} = $echo_handle;

	$self->router($parent);
	$self->request($request);

	$self->response(Carbon::HTTP::Response->new);
	if (defined $self->request) { # stuff like pre-includes don't have an associated request
		$self->query_form($self->request->uri->query_form);
		if (defined $self->request->header('content-type') and $self->request->header('content-type') eq 'application/x-www-form-urlencoded') {
			$self->post_form(parse_urlencoded_form($self->request->content));
			# { map { ($_->[0] // '') => ($_->[1] // '') } map [split('=', $_, 2)], split '&', $self->request->content }
		} elsif (defined $self->request->header('content-type') and $self->request->header('content-type') =~ /\bmultipart\/form-data; boundary=(.*)/) {
			my $boundary = $1;
			# say "debug content length:", $self->request->header('content-length');
			$self->post_form(parse_multipart_form($self->request->content, "--$boundary"));
			# say "processed post form";
		} elsif (defined $self->request->header('content-type') and $self->request->header('content-type') eq 'application/json') {
			$self->post_form(parse_json_form($self->request->content));
		}
	}

	return $self
}

sub router { @_ > 1 ? $_[0]{carbon_anthracite_runtime__router} = $_[1] : $_[0]{carbon_anthracite_runtime__router} }
sub request { @_ > 1 ? $_[0]{carbon_anthracite_runtime__request} = $_[1] : $_[0]{carbon_anthracite_runtime__request} }
sub response { @_ > 1 ? $_[0]{carbon_anthracite_runtime__response} = $_[1] : $_[0]{carbon_anthracite_runtime__response} }
sub query_form { @_ > 1 ? $_[0]{carbon_anthracite_runtime__query_form} = $_[1] : $_[0]{carbon_anthracite_runtime__query_form} }
sub post_form { @_ > 1 ? $_[0]{carbon_anthracite_runtime__post_form} = $_[1] : $_[0]{carbon_anthracite_runtime__post_form} }


sub get_arg {
	my ($self, $key) = @_;
	return $self->query_form->{$key};
}

sub post_arg {
	my ($self, $key) = @_;
	return $self->post_form->{$key};
}


sub echo {
	my $self = shift;
	$self->{carbon_anthracite_runtime__echo_handle}->print(@_);
}

sub include {
	my ($self, $filepath) = @_;
	return $self->router->include_dynamic_file($self, $filepath)
}

sub redirect {
	my ($self, $loc, $permenant) = @_;
	my $res = Carbon::HTTP::Response->new($permenant // 0 ? '301' : '303');
	$res->header('location' => $loc);
	$self->response($res);
	return $res
}

sub warn {
	my ($self) = shift;
	CORE::warn '[' . (caller)[0] . ' warning]: ', @_, "\n";
}

sub die {
	my ($self) = shift;
	CORE::die '[' . (caller)[0] . ' died]: ', @_
}

sub execute {
	my ($self, $compiled) = @_;
	my $ret = eval { $compiled->code->($self) };
	if ($@) {
		$self->warn ("dynamic file died: $@");
		my $res = Carbon::HTTP::Response->new('500');
		$res->content("dynamic file died: $@");
		$res->header('content-type' => 'text/plain');
		$res->header('content-length' => length ($res->content // ''));
		$self->response($res);
	}
	return $ret
}

sub produce_response {
	my ($self) = @_;

	$self->{carbon_anthracite_runtime__echo_handle}->close;
	my $res = $self->response // Carbon::HTTP::Response->new;
	$res->code($res->code // '200');
	$res->content($self->{carbon_anthracite_runtime__output}) unless defined $res->content;
	$res->header('content-length' => length ($res->content // ''));
	$res->header('content-type' => 'text/html') unless defined $res->header('content-type');

	return $res
}



1;
