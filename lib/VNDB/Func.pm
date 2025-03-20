package VNDB::Func;

use v5.36;
use Exporter 'import';
use POSIX 'strftime', 'floor';
use Socket 'inet_pton', 'inet_ntop', 'AF_INET', 'AF_INET6';
use Digest::SHA 'sha1';
use VNDB::Config;
use VNDB::Types;
use VNDB::BBCode;

our @EXPORT = (qw|
    bb_format
    in
    idcmp
    shorten
    resolution
    gtintype
    imgsize
    norm_ip
    minage
    fmtvote fmtmedia fmtage fmtdate fmtrating fmtspoil fmtanimation fmtbirthday
    rdate
    imgpath imgurl thumburl imgiv
    tlang tattr
    md2html
    is_insecurepass
|);


# Simple "is this element in the array?" function, using 'eq' to test equality.
# Supports both an @array and \@array.
# Usage:
#
#   my $contains_hi = in 'hi', qw/ a b hi c /; # true
#
sub in($q, @a) {
    $_ eq $q && return 1 for map ref $_ eq 'ARRAY' ? @$_ : ($_), @a;
    0
}


# Compare two vndbids, using proper numeric order
sub idcmp :prototype($$) ($a,$b) {
    my($a1, $a2) = $a =~ /^([a-z]+)([0-9]+)$/;
    my($b1, $b2) = $b =~ /^([a-z]+)([0-9]+)$/;
    $a1 cmp $b1 || $a2 <=> $b2
}


sub shorten($str, $len) {
    return length($str) > $len ? substr($str, 0, $len-3).'...' : $str;
}


sub resolution($x,$y=0) {
    ($x,$y) = ($x->{reso_x}, $x->{reso_y}) if ref $x;
    $x ? "${x}x${y}" : $y == 1 ? 'Non-standard' : undef
}


# GTIN code as argument,
# Returns 'JAN', 'EAN', 'UPC', 'ISBN' or undef,
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
    return 'ISBN' if /^97[89]/;
    return  undef if /^(?:0[2-5]|2|9[6-9])/; # some codes we don't want: 020–059 & 200-299 & non-ISBN 977-999
    return 'EAN'; # let's just call everything else EAN :)
}


# arguments: <image size>, <max dimensions>
# returns the size of the thumbnail with the same aspect ratio as the full-size
#   image, but fits within the specified maximum dimensions
sub imgsize($ow, $oh, $sw, $sh) {
    return ($ow, $oh) if $ow <= $sw && $oh <= $sh;
    if($ow/$oh > $sw/$sh) { # width is the limiting factor
        $oh *= $sw/$ow;
        $ow = $sw;
    } else {
        $ow *= $sh/$oh;
        $oh = $sh;
    }
    return (int ($ow+0.5), int ($oh+0.5));
}


# Normalized IP address to use for duplicate detection/throttling. For IPv4
# this is the /23 subnet (is this enough?), for IPv6 the /48 subnet, with the
# least significant bits of the address zero'd.
sub norm_ip($ip) {
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


sub minage($age, $ex=0) {
    return 'Unknown' if !defined $age;
    $age = $AGE_RATING{$age};
    $ex && $age->{ex} ? "$age->{txt} (e.g. $age->{ex})" : $age->{txt}
}


sub _path($parent, $id, $dir=undef, $format='jpg') {
    my($type, $num) = $id=~ /([a-z]+)([0-9]+)/;
    sprintf '%s/%s%s/%02d/%d.%s', $parent, $type, $dir ? ".$dir" : '', $num%100, $num, $format;
}

# imgpath($image_id, $dir, $format)
#   $dir = empty || 't' || 'orig'
#   $format = empty || $file_ext
sub imgpath { _path config->{var_path}.'/static', @_ }

# imgurl($image_id, $dir, $format)
sub imgurl { _path config->{url_static}, @_ }

# thumburl($image_obj)
sub thumburl {
    _path config->{url_static}, $_[0]{id},
        $_[0]{id} =~ /^sf/
    || ($_[0]{id} =~ /^cv/ && ($_[0]{width} > config->{cv_size}[0] || $_[0]{height} > config->{cv_size}[1])) ? 't' : undef;
}

# imgiv($image_obj, $cat) - returns <a> attributes for an imageviewer link
sub imgiv {
    (href => imgurl($_[0]{id}), 'data-iv' => "$_[0]{width}x$_[0]{height}:".($_[1]||'').":$_[0]{sexual}$_[0]{violence}$_[0]{votecount}");
}

# Formats a vote number.
sub fmtvote($v) {
    return !$v ? '-' : $v % 10 == 0 ? $v/10 : sprintf '%.1f', $v/10;
}

# Formats a media string ("1 CD", "2 CDs", "Internet download", etc)
sub fmtmedia($med, $qty) {
    $med = $MEDIUM{$med};
    join ' ',
        $qty || (),
        $med->{ $qty > 1 ? 'plural' : 'txt' };
}

# Formats a UNIX timestamp as a '<number> <unit> ago' string
sub fmtage($ts) {
    my $a = time - $ts;
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
sub fmtdate($t, $f=undef) {
    return strftime '%Y-%m-%d', localtime $t if !$f || $f eq 'compact';
    return strftime '%Y-%m-%d at %R', localtime $t;
}

# Turn a (natural number) vote into a rating indication
sub fmtrating($v) {
    ['worst ever',
     'awful',
     'bad',
     'weak',
     'so-so',
     'decent',
     'good',
     'very good',
     'excellent',
     'masterpiece']->[$v-1];
}

# Turn a spoiler level into a string
sub fmtspoil($v) {
    ['neutral',
     'no spoiler',
     'minor spoiler',
     'major spoiler']->[$v+1];
}


sub fmtanimation($a, $cat) {
    return if !defined $a;
    return $cat ? ucfirst "$cat not animated" : 'Not animated' if !$a;
    return $cat ? "No $cat" : 'Not applicable' if $a == 1;
    ($a & 256 ? 'Some scenes ' : $a & 512 ? 'All scenes ' : '').join('/',
        $a &  4 ? 'Hand drawn' : (),
        $a &  8 ? 'Vectorial' : (),
        $a & 16 ? '3D' : (),
        $a & 32 ? 'Live action' : ()
    ).($cat ? " $cat" : '');
}


sub fmtbirthday($b) {
    state @m = qw{January February March April May June July August September October November December};
    $b ? sprintf '%d %s', $b%100, $m[int($b/100)-1] : ''
}


# Format a release date as a string.
sub rdate($date=0) {
    my($y, $m, $d) = ($1, $2, $3) if sprintf('%08d', $date//0) =~ /^([0-9]{4})([0-9]{2})([0-9]{2})$/;
    $y ==    0 ? 'unknown' :
    $y == 9999 ? 'TBA' :
    $m ==   99 ? sprintf('%04d', $y) :
    $d ==   99 ? sprintf('%04d-%02d', $y, $m) :
                 sprintf('%04d-%02d-%02d', $y, $m, $d);
}


# Given a language code & title, returns a (lang => $x) html property.
sub tlang($lang, $title) {
    # TODO: The -Latn suffix is redundant for languages that use the Latin script by default, need to check with a list.
    # English is the site's default, so no need to specify that.
    $lang && $lang ne 'en'
        ? (lang => $lang . ($title =~ /[\x{0400}-\x{04ff}\x{0600}-\x{06ff}\x{0e00}-\x{0e7f}\x{1100}-\x{11ff}\x{1400}-\x{167f}\x{3040}-\x{3099}\x{30a1}-\x{30fa}\x{3100}-\x{9fff}\x{ac00}-\x{d7af}\x{ff66}-\x{ffdc}\x{20000}-\x{323af}]/ ? '' : '-Latn'))
        : ();
}


# Given an SQL titles array, returns element attributes & content.
sub tattr {
    my $title = ref $_[0] eq 'HASH' ? $_[0]{title} : $_[0];
    (tlang($title->[0],$title->[1]), title => $title->[3], $title->[1])
}



sub md2html($markdown) {
    require Text::MultiMarkdown;
    my $html = Text::MultiMarkdown::markdown($markdown, {
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


sub is_insecurepass($pass) {
    utf8::encode(my $utf8 = $pass);
    my $hash = sha1 $utf8;
    my $dir = config->{var_path}.'/hibp';
    return 0 if !-d $dir;

    my $prefix = uc unpack 'H4', $hash;
    my $data = substr $hash, 2, 10;
    my $F;
    if(!open $F, '<', "$dir/$prefix") {
        warn "Unable to lookup password prefix $prefix: $!";
        return 0;
    }

    # Plain old binary search.
    # Would be nicer to search through an mmap'ed view of the file, or at least
    # use pread(), but alas, neither are easily available in Perl.
    my($left, $right) = (0, -10 + -s $F);
    while($left <= $right) {
        my $off = floor(($left+$right)/20)*10;
        sysseek $F, $off, 0 or die $!;
        10 == sysread $F, my $buf, 10 or die $!;
        return 1 if $buf eq $data;
        if($buf lt $data) { $left = $off + 10; }
        else {              $right = $off - 10; }
    }
    0;
}

1;
