package Email::MIME::RFC2047::Decoder;

use strict;

use Encode ();
use MIME::Base64 ();

my $rfc_specials = '()<>\[\]:;\@\\,."';

# Regex for encoded words including leading whitespace.
# This also checks the validity of base64 encoded data because MIME::Base64
# silently ignores invalid characters.
# Captures ($ws, $encoding, $content_b, $content_q)
my $encoded_word_text_re = qr/
    ( ^ | \s+ )
    = \? ( [\w-]+ ) \?
    (?:
        [Bb] \?
        (
            (?:
                [A-Za-z0-9+\/]{2}
                (?: == | [A-Za-z0-9+\/] [A-Za-z0-9+\/=] )
            )+
        ) |
        [Qq] \?
        ( [^?\x00-\x20\x7f-\x{ffff}]+ )
    )
    \? =
    (?= \z | \s+ )
/x;

# Same as $encoded_word_text_re but excluding RFC 822 special chars
# Also matches before special chars
my $encoded_word_phrase_re = qr/
    ( ^ | \s+ )
    = \? ( [\w-]+ ) \?
    (?:
        [Bb] \?
        (
            (?:
                [A-Za-z0-9+\/]{2}
                (?: == | [A-Za-z0-9+\/] [A-Za-z0-9+\/=] )
            )+
        ) |
        [Qq] \?
        ( [^?\x00-\x20$rfc_specials\x7f-\x{ffff}]+ )
    )
    \? =
    (?= \z | \s+ | [$rfc_specials] )
/x;

my $quoted_string_re = qr/
    "
    (
        (?:
            [^"\\] |
            \\ .
        )*
    )
    "
/sx;

sub new {
    my $package = shift;

    my $self = {};

    return bless($self, $package);
}

sub decode_text {
    my ($self, $encoded) = @_;

    return $self->_decode('text', $encoded);
}

sub decode_phrase {
    my ($self, $encoded) = @_;

    return $self->_decode('phrase', $encoded);
}

sub _decode {
    my ($self, $mode, $encoded) = @_;

    my $result = '';
    my $enc_flag;
    # use shortest match on any characters we don't want to decode
    my $regex = $mode eq 'phrase' ?
        qr/([^$rfc_specials]*?)($encoded_word_phrase_re|$quoted_string_re)/ :
        qr/(.*?)($encoded_word_text_re)/;

    while($encoded =~ /\G$regex/cgs) {
        my ($text, $match,
            $ws, $encoding, $b_content, $q_content,
            $qs_content) =
            ($1, $2, $3, $4, $5, $6, $7);

        $result .= $text;

        if(defined($encoding)) {
            # encoded words shouldn't be longer than 75 chars but
            # let's allow up to 255 chars
            if(length($match) - length($ws) > 255) {
                $result .= $match;
                $enc_flag = undef;
                last;
            }

            my $content;

            if(defined($b_content)) {
                # MIME B
                $content = MIME::Base64::decode_base64($b_content);
            }
            else {
                # MIME Q
                $content = $q_content;
                $content =~ tr/_/ /;
                $content =~ s/=([0-9A-Fa-f]{2})/chr(hex($1))/eg;
            }

            my $chunk;
            eval {
                $chunk = Encode::decode(
                    $encoding,
                    $content,
                    Encode::FB_CROAK
                );
            };

            if($@) {
                warn($@);
                # display raw encoded word in case of errors
                $result .= $match;
                $enc_flag = undef;
                last;
            }

            # ignore whitespace between encoded words
            $result .= $ws unless $enc_flag && $text eq '';

            $result .= $chunk;

            $enc_flag = 1;
        }
        else {
            # quoted string, unquote
            $qs_content =~ s/\\(.)/$1/gs;
            $result .= $qs_content;

            $enc_flag = undef;
        }
    }

    $regex = $mode eq 'phrase' ?
        qr/[^$rfc_specials]+/ :
        qr/.+/;
    $result .= $& if $encoded =~ /\G$regex/;

    # normalize whitespace
    $result =~ s/^\s+//;
    $result =~ s/\s+\z//;
    $result =~ s/\s+/ /g;

    # remove potentially dangerous ASCII control chars
    $result =~ s/[\x00-\x1f\x7f]//g;

    return $result;
}

1;

__END__

=head1 NAME

Email::MIME::RFC2047::Decoder - Decoding of non-ASCII MIME headers

=head1 SYNOPSIS

 use Email::MIME::RFC2047::Decoder;
 
 my $decoder = Email::MIME::RFC2047::Decoder->new();
 
 my $string = $decoder->decode_text($encoded_text);
 my $string = $decoder->decode_phrase($encoded_phrase);

=head1 DESCRIPTION

This module decodes parts of MIME email message headers containing non-ASCII
text according to RFC 2047.

=head1 CONSTRUCTOR

=head2 new

 my $decoder = Email::MIME::RFC2047::Decoder->new();

Creates a new decoder object.

=head1 METHODS

=head2 decode_text

 my $string = $decoder->decode_text($encoded_text);

Decodes any MIME header field for which the field body is defined as '*text'
(as defined by RFC 822), for example, any Subject or Comments header field.

This method processes $encoded_text starting from the current search position.
See L<perlfunc/pos>.
 
The resulting string is trimmed and any whitespace is collapsed.

=head2 decode_phrase

 my $string = $decoder->decode_phrase($encoded_phrase);

Decodes any 'phrase' token (as defined by RFC 822) in a MIME header field,
for example, one that precedes an address in a From, To, or Cc header.

This method works like I<decode_text> but additionally unquotes any
'quoted-strings'. It also stops at any special character as defined by
RFC 822. The current search position is set accordingly. This is helpful
when parsing RFC 822 email addresses.

=head1 AUTHOR

Nick Wellnhofer <wellnhofer@aevum.de>

=head1 COPYRIGHT AND LICENSE

Copyright (C) Nick Wellnhofer, 2009

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.0 or,
at your option, any later version of Perl 5 you may have available.

=cut

