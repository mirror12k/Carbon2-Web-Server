package Carbon::HTTP::Request;
use parent 'Carbon::HTTP::Message';
use strict;
use warnings;

# a minimalistic implementation of HTTP::Request

sub new {
	my $class = shift;
	my $self = $class->SUPER::new;

	$self->method(shift) if @_;
	$self->uri(shift) if @_;
	$self->headers(shift // {}) if @_;
	$self->content(shift) if @_;

	return $self
}


sub parse {
	my ($class, $text) = @_;
	my ($head, $body) = split /\r?\n\r?\n/, $text, 2;
	my ($message_line, $headers) = split /\r?\n/, $head, 2;

	my ($method, $uri, $protocol) = split /\s+/, $message_line, 3;

	my $req = $class->new($method // return, $uri // return, undef, $body);
	$req->protocol($protocol // return);
	$req->parse_headers($headers) if defined $headers;

	return $req
}

sub message_line {
	my ($self) = @_;
	return join (' ', $self->method // 'GET', $self->uri // '/', $self->protocol // 'HTTP/1.1')
}

sub method { @_ > 1 ? $_[0]{method} = $_[1] : $_[0]{method} }
sub uri { @_ > 1 ? $_[0]{uri} = $_[1] : $_[0]{uri} }



# sub as_string {
# 	my ($self) = @_;
# 	my $headers = $self->headers;
# 	return join "\r\n",
# 		join (' ', $self->method // 'GET', $self->uri // '/', $self->protocol // 'HTTP/1.1'),
# 		(map "$_: $headers->{$_}", keys %$headers),
# 		'',
# 		$self->content // ''
# }




1
