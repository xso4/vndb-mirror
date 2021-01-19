
package VNDB::Func;

use strict;
use warnings;
use TUWF 'uri_escape';
use Exporter 'import';
use POSIX 'strftime';
use VNDBUtil;
use VNDB::Config;
use VNDB::Types;
use VNDB::BBCode;
our @EXPORT = (@VNDBUtil::EXPORT, 'bb_format', qw|
  minage
  fmtvote fmtmedia fmtage fmtdate fmtrating fmtspoil
  imgpath imgurl
  lang_attr
  query_encode
  md2html
|);


sub minage {
  my($a, $ex) = @_;
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
    my @l = ref $_[0] ? $_[0]->@* : @_;
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
