package VNWeb::Filters;

# This module implements validating old search filters and converting them to
# the new AdvSearch system. It only exists for compatibility with old URLs.

use v5.26;
use TUWF;
use VNDB::Types;
use VNWeb::Auth;
use VNWeb::Validation;
use Exporter 'import';

our @EXPORT = qw/filter_parse filter_vn_adv filter_release_adv filter_char_adv filter_staff_adv/;


my $VN = form_compile any => {
    date_before => { required => 0, uint => 1, range => [0, 99999999] }, # don't use 'rdate' validation here, the search form allows invalid dates
    date_after  => { required => 0, uint => 1, range => [0, 99999999] }, # ^
    released    => { undefbool => 1 },
    length      => { undefarray => { enum => \%VN_LENGTH } },
    hasani      => { undefbool => 1 },
    hasshot     => { undefbool => 1 },
    tag_inc     => { undefarray => { id => 1 } },
    tag_exc     => { undefarray => { id => 1 } },
    taginc      => { undefarray => {} }, # [old] Tag search by name
    tagexc      => { undefarray => {} }, # [old] Tag search by name
    tagspoil    => { required => 0, default => 0, uint => 1, range => [0,2] },
    lang        => { undefarray => { enum => \%LANGUAGE } },
    olang       => { undefarray => { enum => \%LANGUAGE } },
    plat        => { undefarray => { enum => \%PLATFORM } },
    staff_inc   => { undefarray => { id => 1 } },
    staff_exc   => { undefarray => { id => 1 } },
    ul_notblack => { undefbool => 1 },
    ul_onwish   => { undefbool => 1 },
    ul_voted    => { undefbool => 1 },
    ul_onlist   => { undefbool => 1 },
};

my $RELEASE = form_compile any => {
    type        => { required => 0, enum => \%RELEASE_TYPE },
    patch       => { undefbool => 1 },
    freeware    => { undefbool => 1 },
    doujin      => { undefbool => 1 },
    uncensored  => { undefbool => 1 },
    date_before => { required => 0, range => [0, 99999999] }, # don't use 'rdate' validation here, the search form allows invalid dates
    date_after  => { required => 0, range => [0, 99999999] }, # ^
    released    => { undefbool => 1 },
    minage      => { undefarray => { enum => [-1, keys %AGE_RATING] } },
    lang        => { undefarray => { enum => \%LANGUAGE } },
    olang       => { undefarray => { enum => \%LANGUAGE } },
    resolution  => { undefarray => {} },
    plat        => { undefarray => { enum => [ 'unk', keys %PLATFORM ] } },
    prod_inc    => { undefarray => { id => 1 } },
    prod_exc    => { undefarray => { id => 1 } },
    med         => { undefarray => { enum => [ 'unk', keys %MEDIUM ] } },
    voiced      => { undefarray => { enum => \%VOICED } },
    ani_story   => { undefarray => { enum => \%ANIMATED } },
    ani_ero     => { undefarray => { enum => \%ANIMATED } },
    engine      => { required => 0 },
};

my $CHAR = form_compile any => {
    gender      => { undefarray => { enum => \%GENDER } },
    bloodt      => { undefarray => { enum => \%BLOOD_TYPE } },
    bust_min    => { required => 0, uint => 1, range => [ 0, 32767 ] },
    bust_max    => { required => 0, uint => 1, range => [ 0, 32767 ] },
    waist_min   => { required => 0, uint => 1, range => [ 0, 32767 ] },
    waist_max   => { required => 0, uint => 1, range => [ 0, 32767 ] },
    hip_min     => { required => 0, uint => 1, range => [ 0, 32767 ] },
    hip_max     => { required => 0, uint => 1, range => [ 0, 32767 ] },
    height_min  => { required => 0, uint => 1, range => [ 0, 32767 ] },
    height_max  => { required => 0, uint => 1, range => [ 0, 32767 ] },
    weight_min  => { required => 0, uint => 1, range => [ 0, 32767 ] },
    weight_max  => { required => 0, uint => 1, range => [ 0, 32767 ] },
    cup_min     => { required => 0, enum => \%CUP_SIZE },
    cup_max     => { required => 0, enum => \%CUP_SIZE },
    va_inc      => { undefarray => { id => 1 } },
    va_exc      => { undefarray => { id => 1 } },
    trait_inc   => { undefarray => { id => 1 } },
    trait_exc   => { undefarray => { id => 1 } },
    tagspoil    => { required => 0, default => 0, uint => 1, range => [0,2] },
    role        => { undefarray => { enum => \%CHAR_ROLE } },
};

my $STAFF = form_compile any => {
    gender      => { undefarray => { enum => [qw[unknown m f]] } },
    role        => { undefarray => { enum => [ 'seiyuu', keys %CREDIT_TYPE ] } },
    truename    => { undefbool => 1 },
    lang        => { undefarray => { enum => \%LANGUAGE } },
};



# Compatibility with old VN filters. Modifies the filter in-place and returns the number of changes made.
sub filter_vn_compat {
    my($fil) = @_; #XXX: This function is called from old VNDB:: code and the filter data may not have been normalized as per the schema.
    my $mod = 0;

    # older tag specification (by name rather than ID)
    for ('taginc', 'tagexc') {
        my $l = delete $fil->{$_};
        next if !$l;
        $l = [ map lc($_), ref $l ? @$l : $l ];
        $fil->{ s/^tag/tag_/rg } ||= [ map $_->{id}, tuwf->dbAlli(
           'SELECT DISTINCT id FROM tags WHERE searchable AND lower(name) IN', $l
        )->@* ];
        $mod++;
    }

    $mod;
}


# Resolutions were passed as integers into an array index before 6bd0b0cd1f3892253d881f71533940f0cf07c13d.
# New resolutions have been added to this array in the past, so some older filters may reference the wrong resolution.
my @OLDRES = (qw/unknown nonstandard 640x480 800x600 1024x768 1280x960 1600x1200 640x400 960x600 1024x576 1024x600 1024x640 1280x720 1280x800 1366x768 1600x900 1920x1080/);

sub filter_release_compat {
    my($fil) = @_;
    my $mod = 0;
    $fil->{resolution} &&= [ map /^(?:0|[1-9][0-9]*)$/ && $_ <= $#OLDRES ? do { $mod++; $OLDRES[$_] } : $_, $fil->{resolution}->@* ];
    $mod;
}



my @fil_escape = split //, '_ !"#$%&\'()*+,-./:;<=>?@[\]^`{}~';

sub _fil_parse {
    my $str = shift;
    my %r;
    for (split /\./, $str) {
        next if !/^([a-z0-9_]+)-([a-zA-Z0-9_~\x81-\x{ffffff}]+)$/;
        my($f, $v) = ($1, $2);
        my @v = split /~/, $v;
        s/_([0-9]{2})/$1 > $#fil_escape ? '' : $fil_escape[$1]/eg for(@v);
        $r{$f} = @v > 1 ? \@v : $v[0]
    }
    return \%r;
}


# Throws error on failure.
sub filter_parse {
    my($type, $str) = @_;
    return {} if !$str;
    my $s = {v => $VN, r => $RELEASE, c => $CHAR, s => $STAFF}->{$type};
    my $data = ref $str ? $str : $str =~ /^{/ ? JSON::XS->new->decode($str) : _fil_parse $str;
    die "Invalid filter data: $str\n" if !$data;
    my $f = $s->validate($data)->data;
    filter_vn_compat $f if $type eq 'v';
    filter_release_compat $f if $type eq 'r';
    $f
}


sub filter_vn_adv {
    my($fil) = @_;
    [ 'and',
    defined $fil->{date_before} ? [ 'released', '<=', $fil->{date_before} ] : (),
    defined $fil->{date_after}  ? [ 'released', '>=', $fil->{date_after} ] : (),
    defined $fil->{released}    ? [ 'released', $fil->{released} ? '<=' : '>', 1 ] : (),
    defined $fil->{length}      ? [ 'or', map [ 'length', '=', $_ ], $fil->{length}->@* ] : (),
    defined $fil->{hasani}      ? [ 'has-anime', $fil->{hasani} ? '=' : '!=', 1 ] : (),
    defined $fil->{hasshot}     ? [ 'has-screenshot', $fil->{hasshot} ? '=' : '!=', 1 ] : (),
    defined $fil->{tag_inc}     ? [ 'and', map [ 'tag', '=',  [ $_, $fil->{tagspoil}, 0 ] ], $fil->{tag_inc}->@* ] : (),
    defined $fil->{tag_exc}     ? [ 'and', map [ 'tag', '!=', [ $_, 2, 0 ] ], $fil->{tag_exc}->@* ] : (),
    defined $fil->{lang}        ? [ 'or', map [ 'lang',     '=', $_ ], $fil->{lang}->@* ] : (),
    defined $fil->{olang}       ? [ 'or', map [ 'olang',    '=', $_ ], $fil->{olang}->@* ] : (),
    defined $fil->{plat}        ? [ 'or', map [ 'platform', '=', $_ ], $fil->{plat}->@* ] : (),
    defined $fil->{staff_inc}   ? [ 'staff', '=',  [ 'or', map [ 'id', '=', $_ ], $fil->{staff_inc}->@* ] ] : (),
    defined $fil->{staff_exc}   ? [ 'staff', '!=', [ 'or', map [ 'id', '=', $_ ], $fil->{staff_exc}->@* ] ] : (),
    auth ? (
        defined $fil->{ul_notblack}   ? [ 'label', '!=', [ auth->uid, 6 ] ] : (),
        defined $fil->{ul_onwish}     ? [ 'label', $fil->{ul_onwish} ? '=' : '!=', [ auth->uid, 5 ] ] : (),
        defined $fil->{ul_voted}      ? [ 'label', $fil->{ul_voted}  ? '=' : '!=', [ auth->uid, 7 ] ] : (),
        defined $fil->{ul_onlist}     ? [ 'on-list', $fil->{ul_onlist} ? '=' : '!=', 1 ] : (),
    ) : ()
    ]
}


sub filter_release_adv {
    my($fil) = @_;
    [ 'and',
    defined $fil->{type}        ? [ 'rtype', '=', $fil->{type} ] : (),
    defined $fil->{patch}       ? [ 'patch',      $fil->{patch}      ? '=' : '!=', 1 ] : (),
    defined $fil->{freeware}    ? [ 'freeware',   $fil->{freeware}   ? '=' : '!=', 1 ] : (),
    defined $fil->{doujin}      ? [ 'doujin',     $fil->{doujin}     ? '=' : '!=', 1 ] : (),
    defined $fil->{uncensored}  ? [ 'uncensored', $fil->{uncensored} ? '=' : '!=', 1 ] : (),
    defined $fil->{date_before} ? [ 'released', '<=', $fil->{date_before} ] : (),
    defined $fil->{date_after}  ? [ 'released', '>=', $fil->{date_after}  ] : (),
    defined $fil->{released}    ? [ 'released', $fil->{released} ? '<=' : '>', 1 ] : (),
    defined $fil->{minage}      ? [ 'or', map [ 'minage', '=', $_ == -1 ? undef : $_ ], $fil->{minage}->@* ] : (),
    defined $fil->{lang}        ? [ 'or', map [ 'lang', '=', $_ ], $fil->{lang}->@* ] : (),
    defined $fil->{olang}       ? [ 'vn', '=', [ 'or', map [ 'olang', '=', $_ ], $fil->{olang}->@* ] ]  : (),
    defined $fil->{resolution}  ? [ 'or', map [ 'resolution', '=', $_ eq 'unknown' ? [0,0] : $_ eq 'nonstandard' ? [0,1] : [split /x/] ], $fil->{resolution}->@* ] : (),
    defined $fil->{plat}        ? [ 'or', map [ 'platform', '=', $_ eq 'unk' ? '' : $_ ], $fil->{plat}->@* ] : (),
    defined $fil->{prod_inc}    ? [ 'or', map [ 'producer-id', '=', $_ ], $fil->{prod_inc}->@* ] : (),
    defined $fil->{prod_exc}    ? [ 'and', map [ 'producer-id', '!=', $_ ], $fil->{prod_exc}->@* ] : (),
    defined $fil->{med}         ? [ 'or', map [ 'medium', '=', $_ eq 'unk' ? '' : $_ ], $fil->{med}->@* ] : (),
    defined $fil->{voiced}      ? [ 'or', map [ 'voiced', '=', $_ ], $fil->{voiced}->@* ] : (),
    defined $fil->{ani_story}   ? [ 'or', map [ 'animation-story', '=', $_ ], $fil->{ani_story}->@* ] : (),
    defined $fil->{ani_ero}     ? [ 'or', map [ 'animation-ero',   '=', $_ ], $fil->{ani_ero}->@* ]  : (),
    defined $fil->{engine}      ? [ 'engine', '=', $fil->{engine} ] : (),
    ]
}


sub filter_char_adv {
    my($fil) = @_;
    [ 'and',
    defined $fil->{gender}     ? [ 'or', map [ 'sex', '=', $_ ], $fil->{gender}->@* ] : (),
    defined $fil->{bloodt}     ? [ 'or', map [ 'blood-type', '=', $_ ], $fil->{bloodt}->@* ] : (),
    defined $fil->{bust_min}   ? [ 'bust',   '>=', $fil->{bust_min}   ] : (),
    defined $fil->{bust_max}   ? [ 'bust',   '<=', $fil->{bust_max}   ] : (),
    defined $fil->{waist_min}  ? [ 'waist',  '>=', $fil->{waist_min}  ] : (),
    defined $fil->{waist_max}  ? [ 'waist',  '<=', $fil->{waist_max}  ] : (),
    defined $fil->{hip_min}    ? [ 'hips',   '>=', $fil->{hip_min}    ] : (),
    defined $fil->{hip_max}    ? [ 'hips',   '<=', $fil->{hip_max}    ] : (),
    defined $fil->{height_min} ? [ 'height', '>=', $fil->{height_min} ] : (),
    defined $fil->{height_max} ? [ 'height', '<=', $fil->{height_max} ] : (),
    defined $fil->{weight_min} ? [ 'weight', '>=', $fil->{weight_min} ] : (),
    defined $fil->{weight_max} ? [ 'weight', '<=', $fil->{weight_max} ] : (),
    defined $fil->{cup_min}    ? [ 'cup',    '>=', $fil->{cup_min}    ] : (),
    defined $fil->{cup_max}    ? [ 'cup',    '<=', $fil->{cup_max}    ] : (),
    defined $fil->{va_inc}     ? [ 'seiyuu', '=',  [ 'or', map [ 'id', '=', $_ ], $fil->{va_inc}->@* ] ] : (),
    defined $fil->{va_exc}     ? [ 'seiyuu', '!=', [ 'or', map [ 'id', '=', $_ ], $fil->{va_exc}->@* ] ] : (),
    defined $fil->{trait_inc}  ? [ 'and', map [ 'trait', '=',  [ $_, $fil->{tagspoil} ] ], $fil->{trait_inc}->@* ] : (),
    defined $fil->{trait_exc}  ? [ 'and', map [ 'trait', '!=', [ $_, 2 ] ], $fil->{trait_exc}->@* ] : (),
    defined $fil->{role}       ? [ 'or', map [ 'role', '=', $_ ], $fil->{role}->@* ] : (),
    ]
}


# 'truename' filter is ignored, not part of the AdvSearch interface
sub filter_staff_adv {
    my($fil) = @_;
    [ 'and',
    defined $fil->{gender}   ? [ 'or', map [ 'gender', '=', $_ ], $fil->{gender}->@* ] : (),
    defined $fil->{role}     ? [ 'or', map [ 'role', '=', $_ ], $fil->{role}->@* ] : (),
    defined $fil->{lang}     ? [ 'or', map [ 'lang', '=', $_ ], $fil->{lang}->@* ] : (),
    ]
}

1;
