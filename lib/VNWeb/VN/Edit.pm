package VNWeb::VN::Edit;

use VNWeb::Prelude;
use VNWeb::Images::Lib 'enrich_image';
use VNWeb::Releases::Lib;


my $FORM = {
    id         => { default => undef, vndbid => 'v' },
    titles     => { minlength => 1, sort_keys => 'lang', aoh => {
        lang     => { enum => \%LANGUAGE },
        title    => { maxlength => 250 },
        latin    => { default => undef, maxlength => 250 },
        official => { anybool => 1 },
    } },
    alias      => { default => '', maxlength => 500 },
    description=> { default => '', maxlength => 10240 },
    devstatus  => { uint => 1, enum => \%DEVSTATUS },
    olang      => { default => 'ja', enum => \%LANGUAGE },
    length     => { uint => 1, enum => \%VN_LENGTH },
    l_wikidata => { default => undef, uint => 1, max => (1<<31)-1 },
    l_renai    => { default => '', maxlength => 100 },
    relations  => { sort_keys => 'vid', aoh => {
        vid      => { vndbid => 'v' },
        relation => { enum => \%VN_RELATION },
        official => { anybool => 1 },
        title    => { _when => 'out' },
    } },
    anime      => { sort_keys => 'aid', aoh => {
        aid      => { id => 1 },
        title    => { _when => 'out' },
        original => { _when => 'out', default => '' },
    } },
    image      => { default => undef, vndbid => 'cv' },
    image_info => { _when => 'out', default => undef, type => 'hash', keys => $VNWeb::Elm::apis{ImageResult}[0]{aoh} },
    editions   => { sort_keys => 'eid', aoh => {
        eid      => { uint => 1, max => 500 },
        lang     => { default => undef, language => 1 },
        name     => {},
        official => { anybool => 1 },
    } },
    staff      => { sort_keys => ['aid','eid','role'], aoh => {
        aid      => { id => 1 },
        eid      => { default => undef, uint => 1 },
        role     => { enum => \%CREDIT_TYPE },
        note     => { default => '', maxlength => 250 },
        id       => { _when => 'out', vndbid => 's' },
        title    => { _when => 'out' },
        alttitle => { _when => 'out' },
    } },
    seiyuu     => { sort_keys => ['aid','cid'], aoh => {
        aid      => { id => 1 },
        cid      => { vndbid => 'c' },
        note     => { default => '', maxlength => 250 },
        # Staff info
        id       => { _when => 'out', vndbid => 's' },
        title    => { _when => 'out' },
        alttitle => { _when => 'out' },
    } },
    screenshots=> { sort_keys => 'scr', aoh => {
        scr      => { vndbid => 'sf' },
        rid      => { default => undef, vndbid => 'r' },
        info     => { _when => 'out', type => 'hash', keys => $VNWeb::Elm::apis{ImageResult}[0]{aoh} },
    } },
    hidden     => { anybool => 1 },
    locked     => { anybool => 1 },

    authmod    => { _when => 'out', anybool => 1 },
    editsum    => { _when => 'in out', editsum => 1 },
    releases   => { _when => 'out', $VNWeb::Elm::apis{Releases}[0]->%* },
    reltitles  => { _when => 'out', aoh => { id => { vndbid => 'r' }, title => {} } },
    chars      => { _when => 'out', aoh => {
        id       => { vndbid => 'c' },
        title    => {},
        alttitle => {},
    } },
};

my $FORM_OUT = form_compile out => $FORM;
my $FORM_IN  = form_compile in  => $FORM;
my $FORM_CMP = form_compile cmp => $FORM;


TUWF::get qr{/$RE{vrev}/edit} => sub {
    my $e = db_entry tuwf->captures('id', 'rev') or return tuwf->resNotFound;
    return tuwf->resDenied if !can_edit v => $e;

    $e->{authmod} = auth->permDbmod;
    $e->{editsum} = $e->{chrev} == $e->{maxrev} ? '' : "Reverted to revision $e->{id}.$e->{chrev}";

    $e->{titles} = [ sort { $a->{lang} cmp $b->{lang} } $e->{titles}->@* ];
    if($e->{image}) {
        $e->{image_info} = { id => $e->{image} };
        enrich_image 0, [$e->{image_info}];
    } else {
        $e->{image_info} = undef;
    }
    $_->{info} = {id=>$_->{scr}} for $e->{screenshots}->@*;
    enrich_image 0, [map $_->{info}, $e->{screenshots}->@*];

    enrich_merge vid => sql('SELECT id AS vid, title[1+1] AS title FROM', vnt, 'v WHERE id IN'), $e->{relations};
    enrich_merge aid => 'SELECT id AS aid, title_romaji AS title, COALESCE(title_kanji, \'\') AS original FROM anime WHERE id IN', $e->{anime};

    enrich_merge aid => sql('SELECT id, aid, title[1+1], title[1+1+1+1] AS alttitle, sorttitle FROM', staff_aliast, 's WHERE aid IN'), $e->{staff}, $e->{seiyuu};

    # It's possible for older revisions to link to aliases that have been removed.
    # Let's exclude those to make sure the form will at least load.
    $e->{staff}  = [ grep $_->{id}, $e->{staff}->@* ];
    $e->{seiyuu} = [ grep $_->{id}, $e->{seiyuu}->@* ];

    my %CRED;
    $CRED{$_} = keys %CRED for keys %CREDIT_TYPE;
    $e->{staff} = [ sort { $CRED{$a->{role}} <=> $CRED{$b->{role}} || $a->{sorttitle} cmp $b->{sorttitle} || $a->{aid} <=> $b->{aid} } $e->{staff}->@* ];
    $e->{editions} = [ sort { ($a->{lang}||'') cmp ($b->{lang}||'') || $b->{official} cmp $a->{official} || $a->{name} cmp $b->{name} } $e->{editions}->@* ];

    $e->{releases} = releases_by_vn $e->{id};
    $e->{reltitles} = tuwf->dbAlli('
        SELECT DISTINCT r.id, i.title
          FROM releases r
          JOIN releases_vn rv ON rv.id = r.id
          JOIN releases_titles rt ON rt.id = r.id
          JOIN unnest(ARRAY[rt.title,rt.latin]) i(title) ON i.title IS NOT NULL
         WHERE NOT r.hidden AND rv.vid =', \$e->{id}
    );

    $e->{chars} = tuwf->dbAlli('
        SELECT id, title[1+1], title[1+1+1+1] AS alttitle FROM', charst, '
         WHERE NOT hidden AND id IN(SELECT id FROM chars_vns WHERE vid =', \$e->{id},')
         ORDER BY sorttitle, id'
    );

    my $title = titleprefs_obj $e->{olang}, $e->{titles};
    framework_ title => "Edit $title->[1]", dbobj => $e, tab => 'edit',
    sub {
        editmsg_ v => $e, "Edit $title->[1]";
        elm_ VNEdit => $FORM_OUT, $e;
    };
};


TUWF::get qr{/v/add}, sub {
    return tuwf->resDenied if !can_edit v => undef;

    framework_ title => 'Add visual novel',
    sub {
        editmsg_ v => undef, 'Add visual novel';
        elm_ VNEdit => $FORM_OUT, elm_empty($FORM_OUT);
    };
};


elm_api VNEdit => $FORM_OUT, $FORM_IN, sub {
    my $data = shift;
    my $new = !$data->{id};
    my $e = $new ? { id => 0 } : db_entry $data->{id} or return tuwf->resNotFound;
    return elm_Unauth if !can_edit v => $e;

    if(!auth->permDbmod) {
        $data->{hidden} = $e->{hidden}||0;
        $data->{locked} = $e->{locked}||0;
    }
    $data->{description} = bb_subst_links $data->{description};
    $data->{alias} =~ s/\n\n+/\n/;
    die "No title in original language" if !length [grep $_->{lang} eq $data->{olang}, $data->{titles}->@*]->[0]{title};

    validate_dbid 'SELECT id FROM anime WHERE id IN', map $_->{aid}, $data->{anime}->@*;
    validate_dbid 'SELECT id FROM images WHERE id IN', $data->{image} if $data->{image};
    validate_dbid 'SELECT id FROM images WHERE id IN', map $_->{scr}, $data->{screenshots}->@*;
    validate_dbid 'SELECT aid FROM staff_alias WHERE aid IN', map $_->{aid}, $data->{staff}->@*;
    validate_dbid 'SELECT aid FROM staff_alias WHERE aid IN', map $_->{aid}, $data->{seiyuu}->@*;

    # Drop unused staff editions
    my %editions = map defined $_->{eid} ? +($_->{eid},1) : (), $data->{staff}->@*;
    $data->{editions} = [ grep $editions{$_->{eid}}, $data->{editions}->@* ];

    $data->{relations} = [] if $data->{hidden};
    validate_dbid 'SELECT id FROM vn WHERE id IN', map $_->{vid}, $data->{relations}->@*;
    die "Relation with self" if grep $_->{vid} eq $e->{id}, $data->{relations}->@*;

    die "Screenshot without releases assigned" if grep !$_->{rid}, $data->{screenshots}->@*; # This is only the case for *very* old revisions, form disallows this now.
    # Allow linking to deleted or moved releases only if the previous revision also had that.
    # (The form really should encourage the user to fix that, but disallowing the edit seems a bit overkill)
    validate_dbid sub { '
        SELECT r.id FROM releases r JOIN releases_vn rv ON r.id = rv.id WHERE NOT r.hidden AND rv.vid =', \$e->{id}, ' AND r.id IN', $_, '
         UNION
        SELECT rid FROM vn_screenshots WHERE id =', \$e->{id}, 'AND rid IN', $_
    }, map $_->{rid}, $data->{screenshots}->@*;

    # Likewise, allow linking to deleted or moved characters.
    validate_dbid sub { '
        SELECT c.id FROM chars c JOIN chars_vns cv ON c.id = cv.id WHERE NOT c.hidden AND cv.vid =', \$e->{id}, ' AND c.id IN', $_, '
         UNION
        SELECT cid FROM vn_seiyuu WHERE id =', \$e->{id}, 'AND cid IN', $_
    }, map $_->{cid}, $data->{seiyuu}->@*;

    $data->{image_nsfw} = $e->{image_nsfw}||0;
    my %oldscr = map +($_->{scr}, $_->{nsfw}), @{ $e->{screenshots}||[] };
    $_->{nsfw} = $oldscr{$_->{scr}}||0 for $data->{screenshots}->@*;

    return elm_Unchanged if !$new && !form_changed $FORM_CMP, $data, $e;
    my $ch = db_edit v => $e->{id}, $data;
    update_reverse($ch->{nitemid}, $ch->{nrev}, $e, $data);
    elm_Redirect "/$ch->{nitemid}.$ch->{nrev}";
};


sub update_reverse {
    my($id, $rev, $old, $new) = @_;

    my %old = map +($_->{vid}, $_), $old->{relations} ? $old->{relations}->@* : ();
    my %new = map +($_->{vid}, $_), $new->{relations}->@*;

    # Updates to be performed, vid => { vid => x, relation => y, official => z } or undef if the relation should be removed.
    my %upd;

    for my $i (keys %old, keys %new) {
        if($old{$i} && !$new{$i}) {
            $upd{$i} = undef;
        } elsif(!$old{$i} || $old{$i}{relation} ne $new{$i}{relation} || !$old{$i}{official} != !$new{$i}{official}) {
            $upd{$i} = {
                vid      => $id,
                relation => $VN_RELATION{ $new{$i}{relation} }{reverse},
                official => $new{$i}{official}
            };
        }
    }

    for my $i (keys %upd) {
        my $v = db_entry $i;
        $v->{relations} = [
            $upd{$i} ? $upd{$i} : (),
            grep $_->{vid} ne $id, $v->{relations}->@*
        ];
        $v->{editsum} = "Reverse relation update caused by revision $id.$rev";
        db_edit v => $i, $v, 'u1';
    }
}

1;
