package VNWeb::Filters;

# This module implements validating and querying the search filters. I'm not
# sure yet if this filter system will continue to exist in this form or if
# there will be a better advanced search system to replace it, but either way
# we'll need to support these filters for the forseeable future.

use VNWeb::Prelude;
use Exporter 'import';

our @EXPORT = qw/filter_parse filter_vn_query filter_release_query/;


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
    minage      => { undefarray => { enum => \%AGE_RATING } },
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


sub debug_validate {
    my($type, $data) = @_;
    my $s = {vn => $VN, release => $RELEASE, char => $CHAR, staff => $STAFF}->{$type};
    my $v = $s->validate($data);
    if(!$v) {
        warn sprintf "Filter validation failed!\nData: %s\nError: %s", JSON::XS->new->canonical->pretty->encode($data), JSON::XS->new->canonical->pretty->encode($v->err);
    } else {
        #warn sprintf "Filter validated: %sSerialized: %s", JSON::XS->new->canonical->pretty->encode($v->data), VNDB::Func::fil_serialize($v->data);
    }
}


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
           'SELECT DISTINCT id FROM tags LEFT JOIN tags_aliases ON id = tag WHERE searchable AND lower(name) IN', $l, 'OR lower(alias) IN', $l
        )->@* ];
        $mod++;
    }

    $mod;
}


# Throws error on failure.
sub filter_parse {
    my($type, $str) = @_;
    my $s = {v => $VN, r => $RELEASE, c => $CHAR, s => $STAFF}->{$type};
    my $data = ref $str ? $str : $str =~ /^{/ ? JSON::XS->new->decode($str) : VNDB::Func::fil_parse $str, keys $s->{known_keys}->%*;
    die "Invalid filter data: $str\n" if !$data;
    my $f = $s->validate($data)->data;
    filter_vn_compat $f if $type eq 'vn';
    $f
}


# Returns an SQL expression for use in a WHERE clause. Assumption: 'v' is an alias to the vn table being queried.
sub filter_vn_query {
    my($fil) = @_;
    sql_and
    defined $fil->{date_before} ? sql 'v.c_released <=', \$fil->{date_before} : (),
    defined $fil->{date_after}  ? sql 'v.c_released >=', \$fil->{date_after}  : (),
    defined $fil->{released}    ? sql 'v.c_released', $fil->{released} ? '<=' : '>', \strftime('%Y%m%d', gmtime) : (),
    defined $fil->{length}      ? sql 'v.length IN', $fil->{length} : (),
    defined $fil->{hasani}      ? sql($fil->{hasani} ?'':'NOT', 'EXISTS(SELECT 1 FROM vn_anime iva WHERE iva.id = v.id)') : (),
    defined $fil->{hasshot}     ? sql($fil->{hasshot}?'':'NOT', 'EXISTS(SELECT 1 FROM vn_screenshots ivs WHERE ivs.id = v.id)') : (),
    defined $fil->{tag_inc}     ? sql
        'v.id IN(SELECT vid FROM tags_vn_inherit WHERE tag IN', $fil->{tag_inc}, 'AND spoiler <=', \$fil->{tagspoil}, 'GROUP BY vid HAVING COUNT(tag) =', scalar $fil->{tag_inc}->@*, ')' : (),
    defined $fil->{tag_exc}     ? sql 'v.id NOT IN(SELECT vid FROM tags_vn_inherit WHERE tag IN', $fil->{tag_exc}, ')' : (),
    defined $fil->{lang}        ? sql 'v.c_languages && ARRAY', $fil->{lang},  '::language[]' : (),
    defined $fil->{olang}       ? sql 'v.c_olang     && ARRAY', $fil->{olang}, '::language[]' : (),
    defined $fil->{plat}        ? sql 'v.c_platforms && ARRAY', $fil->{plat},  '::platform[]' : (),
    defined $fil->{staff_inc}   ? sql 'v.id     IN(SELECT ivs.id FROM vn_staff ivs JOIN staff_alias isa ON isa.aid = ivs.aid WHERE isa.id IN', $fil->{staff_inc}, ')' : (),
    defined $fil->{staff_exc}   ? sql 'v.id NOT IN(SELECT ivs.id FROM vn_staff ivs JOIN staff_alias isa ON isa.aid = ivs.aid WHERE isa.id IN', $fil->{staff_exc}, ')' : (),
    auth ? (
        # TODO: onwish, voted and onlist should respect the label filters in users.ulist_*
        defined $fil->{ul_notblack}   ? sql 'v.id                         NOT    IN(SELECT vid FROM ulist_vns_labels WHERE uid =', \auth->uid, 'AND lbl =', \6, ')' : (),
        defined $fil->{ul_onwish}     ? sql 'v.id', $fil->{ul_onwish}?'':'NOT', 'IN(SELECT vid FROM ulist_vns_labels WHERE uid =', \auth->uid, 'AND lbl =', \5, ')' : (),
        defined $fil->{ul_voted}      ? sql 'v.id', $fil->{ul_voted} ?'':'NOT', 'IN(SELECT vid FROM ulist_vns_labels WHERE uid =', \auth->uid, 'AND lbl =', \7, ')' : (),
        defined $fil->{ul_onlist}     ? sql 'v.id', $fil->{ul_onlist}?'':'NOT', 'IN(SELECT vid FROM ulist_vns        WHERE uid =', \auth->uid, ')' : (),
    ) : (),
}


# Assumption: 'r' is an alias to the release table being queried.
sub filter_release_query {
    my($fil) = @_;
    sql_and
    defined $fil->{type}        ? sql 'r.type =', \$fil->{type} : (),
    defined $fil->{patch}       ? sql($fil->{patch}     ?'':'NOT', 'r.patch'     ) : (),
    defined $fil->{freeware}    ? sql($fil->{freeware}  ?'':'NOT', 'r.freeware'  ) : (),
    defined $fil->{doujin}      ? sql($fil->{doujin}    ?'':'NOT', 'r.doujin AND NOT r.patch') : (),
    defined $fil->{uncensored}  ? sql($fil->{uncensored}?'':'NOT', 'r.uncensored') : (),
    defined $fil->{date_before} ? sql 'r.released <=', \$fil->{date_before} : (),
    defined $fil->{date_after}  ? sql 'r.released >=', \$fil->{date_after}  : (),
    defined $fil->{released}    ? sql 'r.released', $fil->{released} ? '<=' : '>', \strftime('%Y%m%d', gmtime) : (),
    defined $fil->{minage}      ? sql 'r.minage IN', $fil->{minage} : (),
    defined $fil->{lang}        ? sql 'r.id IN(SELECT irl.id FROM releases_lang irl WHERE irl.lang IN', $fil->{lang}, ')' : (),
    defined $fil->{olang}       ? sql 'r.id IN(SELECT irv.id FROM releases_vn irv JOIN vn iv ON irv.vid = iv.id WHERE iv.c_olang && ARRAY', $fil->{olang}, '::language[])' : (),
    defined $fil->{resolution}  ? sql 'NOT r.patch AND ARRAY[r.reso_x,r.reso_y] IN', [ map $_ eq 'unknown' ? '{0,0}' : $_ eq 'nonstandard' ? '{0,1}' : '{'.(s/x/,/r).'}', $fil->{resolution}->@* ] : (),
    defined $fil->{plat}        ? sql_or(
        grep( /^unk$/, $fil->{plat}->@*) ? sql 'NOT EXISTS(SELECT 1 FROM releases_platforms irp WHERE irp.id = r.id)' : (),
        grep(!/^unk$/, $fil->{plat}->@*) ? sql 'r.id IN(SELECT irp.id FROM releases_platforms irp WHERE irp.platform IN', [grep !/^unk$/, $fil->{plat}->@*], ')' : (),
    ) : (),
    defined $fil->{prod_inc}    ? sql 'r.id     IN(SELECT irp.id FROM releases_producers irp WHERE irp.pid IN', $fil->{prod_inc}, ')' : (),
    defined $fil->{prod_exc}    ? sql 'r.id NOT IN(SELECT irp.id FROM releases_producers irp WHERE irp.pid IN', $fil->{prod_exc}, ')' : (),
    defined $fil->{med}         ? sql_or(
        grep( /^unk$/, $fil->{med}->@*) ? sql 'NOT EXISTS(SELECT 1 FROM releases_media irm WHERE irm.id = r.id)' : (),
        grep(!/^unk$/, $fil->{med}->@*) ? sql 'r.id IN(SELECT irm.id FROM releases_media irm WHERE irm.medium IN', [grep !/^unk$/, $fil->{med}->@*], ')' : (),
    ) : (),
    defined $fil->{voiced}      ? sql 'NOT r.patch AND r.voiced    IN', $fil->{voiced}    : (),
    defined $fil->{ani_story}   ? sql 'NOT r.patch AND r.ani_story IN', $fil->{ani_story} : (),
    defined $fil->{ani_ero}     ? sql 'NOT r.patch AND r.ani_ero   IN', $fil->{ani_ero}   : (),
    defined $fil->{engine}      ? sql 'r.engine =', \$fil->{engine} : (),
}

1;
