package VNWeb::Releases::Edit;

use VNWeb::Prelude;
use VNWeb::Images::Lib 'enrich_image', '$IMGSCHEMA';
use VNWeb::Releases::Lib;


my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    id         => { default => undef, vndbid => 'r' },
    official   => { anybool => 1 },
    patch      => { anybool => 1 },
    freeware   => { anybool => 1 },
    doujin     => { anybool => 1 },
    has_ero    => { anybool => 1 },
    titles     => { minlength => 1, sort_keys => 'lang', aoh => {
        lang      => { enum => \%LANGUAGE },
        mtl       => { anybool => 1 },
        title     => { default => undef, sl => 1, maxlength => 300 },
        latin     => { default => undef, sl => 1, maxlength => 300 },
    } },
    # Titles fetched from the VN entry, for auto-filling
    vntitles   => { _when => 'out', aoh => {
        lang      => {},
        title     => {},
        latin     => { default => undef },
    } },
    olang      => { enum => \%LANGUAGE, default => 'ja' },
    platforms  => { sort_keys => 'platform', aoh => { platform => { enum => \%PLATFORM } } },
    media      => { sort_keys => ['medium', 'qty'], aoh => {
        medium    => { enum => \%MEDIUM },
        qty       => { uint => 1, range => [0,40] },
    } },
    drm        => { sort_keys => 'name', aoh => {
        name      => { sl => 1, maxlength => 128 },
        notes     => { default => '' },
        description => { default => '', maxlength => 10240 },
        map +($_,{anybool=>1}), keys %DRM_PROPERTY
    } },
    gtin       => { gtin => 1 },
    catalog    => { default => '', sl => 1, maxlength => 50 },
    released   => { default => 99999999, min => 1, rdate => 1 },
    minage     => { default => undef, int => 1, enum => \%AGE_RATING },
    uncensored => { undefbool => 1 },
    reso_x     => { uint => 1, range => [0,32767] },
    reso_y     => { uint => 1, range => [0,32767] },
    voiced     => { uint => 1, enum => \%VOICED },
    ani_story  => { uint => 1, enum => \%ANIMATED },
    ani_ero    => { uint => 1, enum => \%ANIMATED },
    ani_story_sp => { default => undef, uint => 1, range => [0,32767] },
    ani_story_cg => { default => undef, uint => 1, range => [0,32767] },
    ani_cutscene => { default => undef, uint => 1, range => [0,32767] },
    ani_ero_sp   => { default => undef, uint => 1, range => [0,32767] },
    ani_ero_cg   => { default => undef, uint => 1, range => [0,32767] },
    ani_face   => { undefbool => 1 },
    ani_bg     => { undefbool => 1 },
    engine     => { default => '', sl => 1, maxlength => 50 },
    notes      => { default => '', maxlength => 10240 },
    extlinks   => { extlinks => 'r' },
    vn         => { sort_keys => 'vid', aoh => {
        vid    => { vndbid => 'v' },
        title  => { _when => 'out' },
        rtype  => { default => 'complete', enum => \%RELEASE_TYPE },
    } },
    producers  => { sort_keys => 'pid', aoh => {
        pid       => { vndbid => 'p' },
        developer => { anybool => 1 },
        publisher => { anybool => 1 },
        name      => { _when => 'out' },
    } },
    images     => { sort_keys => 'img', aoh => {
        img       => { vndbid => 'cv' },
        itype     => { enum => \%RELEASE_IMAGE_TYPE },
        vid       => { vndbid => 'v', default => undef },
        lang      => { default => [], unique => 1, sort => 'str', elems => { enum => \%LANGUAGE } },
        photo     => { anybool => 1 },
        nfo       => { _when => 'out', type => 'hash', keys => $IMGSCHEMA },
    } },
    supersedes => { sort_keys => 'rid', aoh => { rid => { vndbid => 'r' } } },
    vnimages   => { _when => 'out', aoh => $IMGSCHEMA },
    vnreleases => { _when => 'out', aoh => $RELSCHEMA },
    hidden     => { anybool => 1 },
    locked     => { anybool => 1 },
    editsum    => { editsum => 1 },
};


sub vnimages($rid, @vid) {
    my $l = fu->SQL('
      SELECT image AS id FROM vn WHERE image IS NOT NULL AND id', IN \@vid, '
       UNION
      SELECT ri.img AS id
        FROM releases_images ri JOIN releases_vn rv ON rv.id = ri.id JOIN releases r ON r.id = ri.id
       WHERE NOT r.hidden AND (ri.vid IS NULL OR ri.vid = rv.vid) AND rv.vid', IN \@vid,
             $rid ? SQL('AND ri.id <>', $rid) : ()
    )->allh;
    enrich_image 0, $l;
    $l;
}

FU::get qr{/$RE{rrev}/(edit|copy)} => sub($id, $rev, $action) {
    my $e = db_entry $id, $rev or fu->notfound;
    my $copy = $action eq 'copy';
    fu->denied if !can_edit r => $copy ? {} : $e;

    my @empty_fields = (qw/gtin catalog images ani_ero ani_story supersedes extlinks/);
    $e->@{@empty_fields} = $FORM_OUT->empty->@{@empty_fields} if $copy;

    $e->{editsum} = $copy ? "Copied from $e->{id}.$e->{chrev}" : $e->{chrev} == $e->{maxrev} ? '' : "Reverted to revision $e->{id}.$e->{chrev}";

    $e->{vntitles} = $e->{vn}->@* == 1 ? fu->sql('SELECT lang, title, latin FROM vn_titles WHERE id = $1', $e->{vn}[0]{vid})->allh : [];

    enrich_image 0, [map { $_->{lang} //= []; $_->{nfo}{id} = $_->{img}; $_->{nfo} } $e->{images}->@*];
    $e->{vnimages} = vnimages $e->{id}, map $_->{vid}, $e->{vn}->@*;
    $e->{vnreleases} = [ grep $copy || $_->{id} ne $e->{id}, releases_by_vn([map $_->{vid}, $e->{vn}->@*])->@* ];

    $_->{title} = $_->{title}[1] for $e->{vn}->@*;
    $_->{name} = $_->{title}[1] for $e->{producers}->@*;

    my $title = ($copy ? 'Copy ' : 'Edit ').titleprefs_obj($e->{olang}, $e->{titles})->[1];
    framework_ title => $title, dbobj => $e, tab => $action,
    sub {
        editmsg_ r => $e, $title, $copy;
        div_ widget(ReleaseEdit => $FORM_OUT, $copy ? {%$e, id=>undef} : $e), '';
    };
};


FU::get qr{/$RE{vid}/add}, sub($vid) {
    fu->denied if !can_edit r => undef;
    my $v = fu->SQL('SELECT id, title FROM', VNT, 'v WHERE NOT hidden AND v.id =', $vid)->rowh or fu->notfound;

    my $delrel = fu->SQL('SELECT r.id, r.title FROM', RELEASEST, 'r JOIN releases_vn rv ON rv.id = r.id WHERE r.hidden AND rv.vid =', $v->{id}, 'ORDER BY id')->allh;
    fu->enrich(aov => 'languages', 'SELECT id, lang FROM releases_titles WHERE id', $delrel);

    my $e = {
        $FORM_OUT->empty->%*,
        vn         => [{vid => $v->{id}, title => $v->{title}[1], rtype => 'complete'}],
        vntitles   => fu->sql('SELECT lang, title, latin FROM vn_titles WHERE id = $1', $v->{id})->allh,
        vnimages   => vnimages(undef, $v->{id}),
        vnreleases => releases_by_vn($v->{id}),
        official   => 1,
    };

    framework_ title => "Add release to $v->{title}[1]",
    sub {
        editmsg_ r => undef, "Add release to $v->{title}[1]";

        article_ sub {
            h1_ 'Deleted releases';
            div_ class => 'warning', sub {
                p_ q{This visual novel has releases that have been deleted
                    before. Please review this list to make sure you're not
                    adding a release that has already been deleted.};
                br_;
                ul_ sub {
                    li_ sub {
                        txt_ '['.join(',', $_->{languages}->@*)."] $_->{id}:";
                        a_ href => "/$_->{id}", tattr $_;
                    } for @$delrel;
                }
            }
        } if @$delrel;

        div_ widget(ReleaseEdit => $FORM_OUT, $e), '';
    };
};


js_api ReleaseEdit => $FORM_IN, sub {
    my $data = shift;
    my $new = !$data->{id};
    my $e = $new ? { id => 0 } : db_entry $data->{id} or fu->notfound;
    fu->denied if !can_edit r => $e;

    if(!auth->permDbmod) {
        $data->{hidden} = $e->{hidden}||0;
        $data->{locked} = $e->{locked}||0;
    }

    $data->{gtin} &&= int $data->{gtin};
    if($data->{patch}) {
        $data->{doujin} = $data->{ani_story} = $data->{ani_ero} = 0;
        $data->{ani_story_sp} = $data->{ani_story_cg} = $data->{ani_cutscene} = $data->{ani_ero_sp} = $data->{ani_ero_cg} = $data->{ani_face} = $data->{ani_bg} = undef;
    }
    if(!$data->{has_ero}) {
        $data->{uncensored} = undef;
        $data->{ani_ero} = 0;
        $data->{ani_ero_sp} = $data->{ani_ero_cg} = undef;
    }
    $data->{images} = [] if !$data->{official};
    ani_compat($data, $e);

    die "No title in main language" if !length [grep $_->{lang} eq $data->{olang}, $data->{titles}->@*]->[0]{title};

    $_->{qty} = 0 for grep !$MEDIUM{$_->{medium}}{qty}, $data->{media}->@*;
    $data->{notes} = bb_subst_links $data->{notes};
    die "No VNs selected" if !$data->{vn}->@*;
    die "Invalid resolution: ($data->{reso_x},$data->{reso_y})" if (!$data->{reso_x} && $data->{reso_y} > 1) || ($data->{reso_x} && !$data->{reso_y});

    my %vids = map +($_->{vid},1), $data->{vn}->@*;
    my %langs = map +($_->{lang},1), $data->{titles}->@*;
    for my $i ($data->{images}->@*) {
        $i->{vid} = undef if $i->{vid} && !$vids{$i->{vid}};
        $i->{lang} = [ grep $langs{$_}, $i->{lang}->@* ];
        $i->{lang} = undef if !$i->{lang}->@* || $i->{lang}->@* == keys %langs;
        $i->{photo} = 0 if $i->{itype} eq 'dig';
    }

    # We need the DRM identifiers to actually save the new form.
    fu->enrich(merge => 1, key => 'name', 'SELECT name, id AS drm FROM drm WHERE name', $data->{drm});
    for my $d ($data->{drm}->@*) {
        $d->{notes} = bb_subst_links $d->{notes};
        $d->{drm} = fu->SQL('INSERT INTO drm', VALUES({map +($_,$d->{$_}), 'name', 'description', keys %DRM_PROPERTY}), 'RETURNING id')->val
            if !defined $d->{drm};
    }

    $data->{supersedes} = [] if $data->{hidden};
    validate_dbid sub { SQL
        'SELECT id FROM releases
          WHERE NOT hidden AND id', IN $_, '
            AND id IN(SELECT id FROM releases_vn WHERE vid', IN [ map $_->{vid}, $data->{vn}->@* ], ')',
            $new ? () : SQL('AND id NOT IN(WITH RECURSIVE s(id) AS (SELECT', $data->{id}, '::vndbid UNION SELECT rs.id FROM releases_supersedes rs JOIN s ON s.id = rs.rid) SELECT id FROM s)'),
    }, map $_->{rid}, $data->{supersedes}->@*;

    VNDB::ExtLinks::normalize $e, $data;

    my $ch = db_edit r => $e->{id}, $data;
    return 'No changes' if !$ch->{nitemid};
    +{ _redir => "/$ch->{nitemid}.$ch->{nrev}" };
};


# Set the old ani_story and ani_ero fields to some sort of value based on the
# new ani_* fields, if they've been changed.
sub ani_compat {
    my($r, $old) = @_;
    return if !grep +($r->{$_}//'_undef_') ne ($old->{$_}//'_undef_'),
        qw{ ani_story_sp ani_story_cg ani_cutscene ani_ero_sp ani_ero_cg ani_face ani_bg };

    my sub known :prototype($) { defined $r->{"ani_$_[0]"} }
    my sub hasani :prototype($) { $r->{"ani_$_[0]"} && $r->{"ani_$_[0]"} > 1 }
    my sub someani :prototype($) { hasani $_[0] && ($r->{"ani_$_[0]"} & 512) == 0 }
    my sub fullani :prototype($) { defined $r->{"ani_$_[0]"} && ($r->{"ani_$_[0]"} & 512) > 0 }

    $r->{ani_story} =
        !known  'story_sp' && !known  'story_cg' && !known  'cutscene' ? 0 :
        !hasani 'story_sp' && !hasani 'story_cg' && !hasani 'cutscene' ? 1 :
        (fullani 'story_sp' || fullani 'story_cg') && !(someani 'story_sp' || someani 'story_cg') ? 4 : 3;

    $r->{ani_ero} =
        !known  'ero_sp' && !known  'ero_cg' ? 0 :
        !hasani 'ero_sp' && !hasani 'ero_cg' ? 1 :
        (fullani 'ero_sp' || fullani 'ero_cg') && !(someani 'ero_sp' || someani 'ero_cg') ? 4 : 3;

    $r->{ani_story} = 2 if $r->{ani_story} < 2 && ($r->{ani_face} || $r->{ani_bg});
}


1;
