package Carbon::HTTP::Util;
use strict;
use warnings;

use feature 'say';

use JSON;

use base 'Exporter';

our @EXPORT = qw/
	parse_urlencoded_form
	parse_multipart_form
	parse_json_form
/;



sub parse_urlencoded_form {
	my ($text) = @_;
	return {
			map { ($_->[0] // '') => ($_->[1] // '') } map [split('=', $_, 2)], split '&', $text
	};
}

sub parse_multipart_form {
	my ($text, $boundary) = @_;
	# say "debug text: $text", unpack 'H*', $text;
	my @segments = split quotemeta ("$boundary"), $text;
	@segments = @segments[1 .. $#segments - 1]; # drop first and last segments
	# say "got segment: $_" for @segments;
	my %parsed_form;
	foreach my $segment (@segments) {
		my ($header, $data) = split /\r\n\r\n/, $segment, 2;

		$header =~ s/\A\r\n//s;
		$data =~ s/\r\n\Z//s;

		my @header_fields = split /\r\n/, $header;
		# say "segment header: $_" foreach @header_fields;
		# say "segment data: $data";

		my ($content_disposition) = grep /\Acontent-disposition:/i, @header_fields;

		next unless defined $content_disposition;
		next unless $content_disposition =~ /\bname="(.*?)"/;

		$parsed_form{$1} = $data;
	}
	return \%parsed_form;
}

sub parse_json_form {
	my ($text) = @_;
	return decode_json($text);
}

1;
