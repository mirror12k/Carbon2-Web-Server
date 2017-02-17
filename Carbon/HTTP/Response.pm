package Carbon::HTTP::Response;
use parent 'Carbon::Message';
use strict;
use warnings;

# a minimalistic implementation of HTTP::Response

# copied and reduced from HTTP::Status
our %CARBON_STATUS_CODES = (
	100 => 'Continue',
	101 => 'Switching Protocols',

	200 => 'OK',

	300 => 'Multiple Choices',
	301 => 'Moved Permanently',
	302 => 'Found',
	303 => 'See Other',
	304 => 'Not Modified',
	307 => 'Temporary Redirect',
	308 => 'Permanent Redirect',

	400 => 'Bad Request',
	401 => 'Unauthorized',
	403 => 'Forbidden',
	404 => 'Not Found',
	405 => 'Method Not Allowed',

	500 => 'Internal Server Error',
);



sub new {
	my $class = shift;
	my $self = $class->SUPER::new;

	$self->code(shift) if @_;
	$self->message(shift) if @_;
	$self->headers(shift // {});
	$self->content(shift) if @_;

	return $self
}

sub parse {
	my ($class, $text) = @_;
	my ($head, $body) = split /\r?\n\r?\n/, $text, 2;
	my ($message_line, $headers) = split /\r?\n/, $head, 2;

	my ($protocol, $code, $message) = split /\s+/, $message_line, 3;

	my $res = $class->new($code // return, $message // return, undef, $body);
	$res->protocol($protocol // return);
	$res->parse_headers($headers) if defined $headers;

	return $res
}



sub code { @_ > 1 ? $_[0]{code} = $_[1] : $_[0]{code} }
sub message { @_ > 1 ? $_[0]{message} = $_[1] : $_[0]{message} }
sub request { @_ > 1 ? $_[0]{request} = $_[1] : $_[0]{request} }



sub status_line {
	my ($self) = @_;
	return $self->code . ' ' . $self->message
}

sub message_line {
	my ($self) = @_;
	return join (' ', $self->protocol // 'HTTP/1.1', $self->code // '200', $self->message // $CARBON_STATUS_CODES{$self->code // '200'} // 'OK')
}


sub is_info { ($_[0]->code // '') =~ /^1\d\d$/ }
sub is_success { ($_[0]->code // '') =~ /^2\d\d$/ }
sub is_redirect { ($_[0]->code // '') =~ /^3\d\d$/ }
sub is_error { ($_[0]->code // '') =~ /^[45]\d\d$/ }
sub is_client_error { ($_[0]->code // '') =~ /^4\d\d$/ }
sub is_server_error { ($_[0]->code // '') =~ /^5\d\d$/ }


# sub as_string {
# 	my ($self) = @_;
# 	my $headers = $self->headers;
# 	return join "\r\n",
# 		join (' ', $self->protocol // 'HTTP/1.1', $self->code // '200', $self->message // $CARBON_STATUS_CODES{$self->code} // 'OK'),
# 		(map "$_: $headers->{$_}", keys %$headers),
# 		'',
# 		$self->content // ''
# }


1
