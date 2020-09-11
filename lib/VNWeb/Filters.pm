package VNWeb::Filters;

# This module implements validating and querying the search filters. I'm not
# sure yet if this filter system will continue to exist in this form or if
# there will be a better advanced search system to replace it, but either way
# we'll need to support these filters for the forseeable future.

use VNWeb::Prelude;

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

1;
