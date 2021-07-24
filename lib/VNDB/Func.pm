package VNDB::Func;

use strict;
use warnings;
use TUWF::Misc 'uri_escape';
use Exporter 'import';
use POSIX 'strftime';
use Encode 'encode_utf8';
use Unicode::Normalize 'NFKD', 'compose';
use Socket 'inet_pton', 'inet_ntop', 'AF_INET', 'AF_INET6';
use VNDB::Config;
use VNDB::Types;
use VNDB::BBCode;
our @EXPORT = ('bb_format', qw|
  in
  idcmp
  shorten
  resolution
  gtintype
  normalize_titles normalize_query
  imgsize
  norm_ip
  minage
  fmtvote fmtmedia fmtage fmtdate fmtrating fmtspoil
  imgpath imgurl
  lang_attr
  query_encode
  md2html
|);


# Simple "is this element in the array?" function, using 'eq' to test equality.
# Supports both an @array and \@array.
# Usage:
#
#   my $contains_hi = in 'hi', qw/ a b hi c /; # true
#
sub in {
    my($q, @a) = @_;
    $_ eq $q && return 1 for map ref $_ eq 'ARRAY' ? @$_ : ($_), @a;
    0
}


# Compare two vndbids, using proper numeric order
sub idcmp($$) {
    my($a1, $a2) = $_[0] =~ /^([a-z]+)([0-9]+)$/;
    my($b1, $b2) = $_[1] =~ /^([a-z]+)([0-9]+)$/;
    $a1 cmp $b1 || $a2 <=> $b2
}


sub shorten {
  my($str, $len) = @_;
  return length($str) > $len ? substr($str, 0, $len-3).'...' : $str;
}


sub resolution {
  my($x,$y) = @_;
  ($x,$y) = ($x->{reso_x}, $x->{reso_y}) if ref $x;
  $x ? "${x}x${y}" : $y == 1 ? 'Non-standard' : undef
}


# GTIN code as argument,
# Returns 'JAN', 'EAN', 'UPC' or undef,
# Also 'normalizes' the first argument in place
sub gtintype {
  $_[0] =~ s/[^\d]+//g;
  $_[0] =~ s/^0+//;
  return undef if $_[0] !~ /^[0-9]{10,13}$/; # I've yet to see a UPC code shorter than 10 digits assigned to a game
  $_[0] = ('0'x(12-length $_[0])) . $_[0] if length($_[0]) < 12; # pad with zeros to GTIN-12
  my $c = shift;
  return undef if $c !~ /^[0-9]{12,13}$/;
  $c = "0$c" if length($c) == 12; # pad with another zero for GTIN-13

  # calculate check digit according to
  #  http://www.gs1.org/productssolutions/barcodes/support/check_digit_calculator.html#how
  my @n = reverse split //, $c;
  my $n = shift @n;
  $n += $n[$_] * ($_ % 2 != 0 ? 1 : 3) for (0..$#n);
  return undef if $n % 10 != 0;

  # Do some rough guesses based on:
  #  http://www.gs1.org/productssolutions/barcodes/support/prefix_list.html
  #  and http://en.wikipedia.org/wiki/List_of_GS1_country_codes
  local $_ = $c;
  return 'JAN' if /^4[59]/; # prefix code 450-459 & 490-499
  return 'UPC' if /^(?:0[01]|0[6-9]|13|75[45])/; # prefix code 000-019 & 060-139 & 754-755
  return  undef if /^(?:0[2-5]|2|97[789]|9[6-9])/; # some codes we don't want: 020–059 & 200-299 & 977-999
  return 'EAN'; # let's just call everything else EAN :)
}


# a rather aggressive normalization
sub normalize {
  local $_ = lc shift;
  use utf8;
  # Remove combining markings, except for kana.
  # This effectively removes all accents from the characters (e.g. é -> e)
  $_ = compose(NFKD($_) =~ s/(?<=[^ア-ンあ-ん])\pM//rg);
  # remove some characters that have no significance when searching
  tr/\r\n\t,_\-.~～〜∼ー῀:[]()%+!?#$"'`♥★☆♪†「」『』【】・‟“”‛’‘‚„«‹»›//d;
  tr/@/a/;
  tr/ı/i/; # Turkish lowercase i
  tr/×/x/;
  s/&/and/;
  # Remove spaces. We're doing substring search, so let it cross word boundary to find more stuff
  tr/ //d;
  # remove commonly used release titles ("x Edition" and "x Version")
  # this saves some space and speeds up the search
  s/(?:
    first|firstpress|firstpresslimited|limited|regular|standard
   |package|boxed|download|complete|popular
   |lowprice|best|cheap|budget
   |special|trial|allages|fullvoice
   |cd|cdr|cdrom|dvdrom|dvd|dvdpack|dvdpg|windows
   |初回限定|初回|限定|通常|廉価|パッケージ|ダウンロード
   )(?:edition|version|版|生産)//xg;
  # other common things
  s/fandisk/fandisc/g;
  s/sempai/senpai/g;
  no utf8;
  return $_;
}


# normalizes each title and returns a concatenated string of unique titles
sub normalize_titles {
  my %t = map +(normalize($_), 1), @_;
  return join ' ', grep length $_, sort keys %t;
}


sub normalize_query {
  my $q = shift;
  # remove spaces within quotes, so that it's considered as one search word
  $q =~ s/"([^"]+)"/(my $s=$1)=~y{ }{}d;$s/ge;
  # split into search words and normalize
  return map quotemeta($_), grep length $_, map normalize($_), split / /, $q;
}


# arguments: <image size>, <max dimensions>
# returns the size of the thumbnail with the same aspect ratio as the full-size
#   image, but fits within the specified maximum dimensions
sub imgsize {
  my($ow, $oh, $sw, $sh) = @_;
  return ($ow, $oh) if $ow <= $sw && $oh <= $sh;
  if($ow/$oh > $sw/$sh) { # width is the limiting factor
    $oh *= $sw/$ow;
    $ow = $sw;
  } else {
    $ow *= $sh/$oh;
    $oh = $sh;
  }
  return (int $ow, int $oh);
}


# Normalized IP address to use for duplicate detection/throttling. For IPv4
# this is the /23 subnet (is this enough?), for IPv6 the /48 subnet, with the
# least significant bits of the address zero'd.
sub norm_ip {
    my $ip = shift;

    # There's a whole bunch of IP manipulation modules on CPAN, but many seem
    # quite bloated and still don't offer the functionality to return an IP
    # with its mask applied (admittedly not a common operation). The libc
    # socket functions will do fine in parsing and formatting addresses, and
    # the actual masking is quite trivial in binary form.
    my $v4 = inet_pton AF_INET, $ip;
    if($v4) {
      $v4 =~ s/(..)(.)./$1 . chr(ord($2) & 254) . "\0"/se;
      return inet_ntop AF_INET, $v4;
    }

    $ip = inet_pton AF_INET6, $ip;
    return '::' if !$ip;
    $ip =~ s/^(.{6}).+$/$1 . "\0"x10/se;
    return inet_ntop AF_INET6, $ip;
}


sub minage {
  my($a, $ex) = @_;
  return 'Unknown' if !defined $a;
  $a = $AGE_RATING{$a};
  $ex && $a->{ex} ? "$a->{txt} (e.g. $a->{ex})" : $a->{txt}
}


sub _path {
    my($t, $id) = $_[1] =~ /([a-z]+)([0-9]+)/;
    $t = 'st' if $t eq 'sf' && $_[2];
    sprintf '%s/%s/%02d/%d.jpg', $_[0], $t, $id%100, $id;
}

# imgpath($image_id, $thumb)
sub imgpath { _path config->{root}.'/static', @_ }

# imgurl($image_id, $thumb)
sub imgurl { _path config->{url_static}, @_ }


# Formats a vote number.
sub fmtvote {
  return !$_[0] ? '-' : $_[0] % 10 == 0 ? $_[0]/10 : sprintf '%.1f', $_[0]/10;
}

# Formats a media string ("1 CD", "2 CDs", "Internet download", etc)
sub fmtmedia {
  my($med, $qty) = @_;
  $med = $MEDIUM{$med};
  join ' ',
    ($med->{qty} ? ($qty) : ()),
    $med->{ $med->{qty} && $qty > 1 ? 'plural' : 'txt' };
}

# Formats a UNIX timestamp as a '<number> <unit> ago' string
sub fmtage {
  my $a = time-shift;
  my($t, $single, $plural) =
    $a > 60*60*24*365*2       ? ( $a/60/60/24/365,      'year',  'years'  ) :
    $a > 60*60*24*(365/12)*2  ? ( $a/60/60/24/(365/12), 'month', 'months' ) :
    $a > 60*60*24*7*2         ? ( $a/60/60/24/7,        'week',  'weeks'  ) :
    $a > 60*60*24*2           ? ( $a/60/60/24,          'day',   'days'   ) :
    $a > 60*60*2              ? ( $a/60/60,             'hour',  'hours'  ) :
    $a > 60*2                 ? ( $a/60,                'min',   'min'    ) :
                                ( $a,                   'sec',   'sec'    );
  $t = sprintf '%d', $t;
  sprintf '%d %s ago', $t, $t == 1 ? $single : $plural;
}


# argument: unix timestamp and optional format (compact/full)
sub fmtdate {
  my($t, $f) = @_;
  return strftime '%Y-%m-%d', gmtime $t if !$f || $f eq 'compact';
  return strftime '%Y-%m-%d at %R', gmtime $t;
}

# Turn a (natural number) vote into a rating indication
sub fmtrating {
  ['worst ever',
   'awful',
   'bad',
   'weak',
   'so-so',
   'decent',
   'good',
   'very good',
   'excellent',
   'masterpiece']->[shift()-1];
}

# Turn a spoiler level into a string
sub fmtspoil {
  ['neutral',
   'no spoiler',
   'minor spoiler',
   'major spoiler']->[shift()+1];
}


# Generates a HTML 'lang' attribute given a list of possible languages.
# This is used for the 'original language' field, which we can safely assume is not used for latin-alphabet languages.
sub lang_attr {
    my @l = map ref($_) eq 'HASH' ? $_->{lang} : $_, ref $_[0] ? $_[0]->@* : @_;
    # Choose Japanese, Chinese or Korean (in order of likelyness) if those are in the list.
    return (lang => 'ja') if grep $_ eq 'ja', @l;
    return (lang => 'zh') if grep $_ eq 'zh', @l;
    return (lang => 'ko') if grep $_ eq 'ko', @l;
    return (lang => $l[0]) if @l == 1;
    ()
}



# Encode query parameters. Takes a hash or hashref with key/values, supports array values and objects that implement query_encode().
sub query_encode {
    my $o = @_ == 1 ? $_[0] : {@_};
    return join '&', map {
        my($k, $v) = ($_, $o->{$_});
        $v = $v->query_encode() if ref $v && ref $v ne 'ARRAY';
        !defined $v ? () : ref $v ? map "$k=".uri_escape($_), sort @$v : "$k=".uri_escape($v)
    } sort keys %$o;
}


sub md2html {
    require Text::MultiMarkdown;
    my $html = Text::MultiMarkdown::markdown(shift, {
        strip_metadata => 1,
        img_ids => 0,
        disable_footnotes => 1,
        disable_bibliography => 1,
    });

    # Number sections and turn them into links
    my($sec, $subsec) = (0,0);
    $html =~ s{<h([1-2])[^>]+>(.*?)</h\1>}{
        if($1 == 1) {
            $sec++;
            $subsec = 0;
            qq{<h3><a href="#$sec" name="$sec">$sec. $2</a></h3>}
        } elsif($1 == 2) {
            $subsec++;
            qq|<h4><a href="#$sec.$subsec" name="$sec.$subsec">$sec.$subsec. $2</a></h4>\n|
        }
    }ge;

    # Text::MultiMarkdown doesn't handle fenced code blocks properly. The
    # following solution breaks inline code blocks, but I don't use those anyway.
    $html =~ s/<code>/<pre>/g;
    $html =~ s#</code>#</pre>#g;
    $html
}

1;
