package VNWeb::VN::Edit;

use VNWeb::Prelude;
use VNWeb::Images::Lib 'enrich_image';
use VNWeb::Releases::Lib;


my $FORM = {
    id         => { required => 0, vndbid => 'v' },
    titles     => { sort_keys => 'lang', aoh => {
        lang     => { enum => \%LANGUAGE },
        title    => { maxlength => 250 },
        latin    => { required => 0, default => undef, maxlength => 250 },
        official => { anybool => 1 },
    } },
    alias      => { required => 0, default => '', maxlength => 500 },
    desc       => { required => 0, default => '', maxlength => 10240 },
    devstatus  => { uint => 1, enum => \%DEVSTATUS },
    olang      => { enum => \%LANGUAGE, default => 'ja' },
    length     => { uint => 1, enum => \%VN_LENGTH },
    l_wikidata => { required => 0, uint => 1, max => (1<<31)-1 },
    l_renai    => { required => 0, default => '', maxlength => 100 },
    relations  => { sort_keys => 'vid', aoh => {
        vid      => { vndbid => 'v' },
        relation => { enum => \%VN_RELATION },
        official => { anybool => 1 },
        title    => { _when => 'out' },
    } },
    anime      => { sort_keys => 'aid', aoh => {
        aid      => { id => 1 },
        title    => { _when => 'out' },
        original => { _when => 'out', required => 0, default => '' },
    } },
    image      => { required => 0, vndbid => 'cv' },
    image_info => { _when => 'out', required => 0, type => 'hash', keys => $VNWeb::Elm::apis{ImageResult}[0]{aoh} },
    editions   => { sort_keys => 'eid', aoh => {
        eid      => { uint => 1, max => 500 },
        lang     => { required => 0, language => 1 },
        name     => {},
        official => { anybool => 1 },
    } },
    staff      => { sort_keys => ['aid','eid','role'], aoh => {
        aid      => { id => 1 },
        eid      => { required => 0, uint => 1 },
        role     => { enum => \%CREDIT_TYPE },
        note     => { required => 0, default => '', maxlength => 250 },
        id       => { _when => 'out', vndbid => 's' },
        name     => { _when => 'out' },
        original => { _when => 'out', required => 0, default => '' },
    } },
    seiyuu     => { sort_keys => ['aid','cid'], aoh => {
        aid      => { id => 1 },
        cid      => { vndbid => 'c' },
        note     => { required => 0, default => '', maxlength => 250 },
        # Staff info
        id       => { _when => 'out', vndbid => 's' },
        name     => { _when => 'out' },
        original => { _when => 'out', required => 0, default => '' },
    } },
    screenshots=> { sort_keys => 'scr', aoh => {
        scr      => { vndbid => 'sf' },
        rid      => { required => 0, vndbid => 'r' },
        info     => { _when => 'out', type => 'hash', keys => $VNWeb::Elm::apis{ImageResult}[0]{aoh} },
    } },
    hidden     => { anybool => 1 },
    locked     => { anybool => 1 },

    authmod    => { _when => 'out', anybool => 1 },
    editsum    => { _when => 'in out', editsum => 1 },
    releases   => { _when => 'out', $VNWeb::Elm::apis{Releases}[0]->%* },
    chars      => { _when => 'out', aoh => {
        id       => { vndbid => 'c' },
        name     => {},
        original => { required => 0, default => '' },
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

    enrich_merge vid => 'SELECT id AS vid, title, alttitle FROM vnt WHERE id IN', $e->{relations};
    enrich_merge aid => 'SELECT id AS aid, title_romaji AS title, COALESCE(title_kanji, \'\') AS original FROM anime WHERE id IN', $e->{anime};

    enrich_merge aid => 'SELECT id, aid, name, original FROM staff_alias WHERE aid IN', $e->{staff}, $e->{seiyuu};

    # It's possible for older revisions to link to aliases that have been removed.
    # Let's exclude those to make sure the form will at least load.
    $e->{staff}  = [ grep $_->{id}, $e->{staff}->@* ];
    $e->{seiyuu} = [ grep $_->{id}, $e->{seiyuu}->@* ];

    $e->{editions} = [ sort { ($a->{lang}||'') cmp ($b->{lang}||'') || $b->{official} cmp $a->{official} || $a->{name} cmp $b->{name} } $e->{editions}->@* ];

    $e->{releases} = releases_by_vn $e->{id};

    $e->{chars} = tuwf->dbAlli('
        SELECT id, name, original FROM chars
         WHERE NOT hidden AND id IN(SELECT id FROM chars_vns WHERE vid =', \$e->{id},')
         ORDER BY name, id'
    );

    my $title = tuwf->dbVali('SELECT title FROM vnt WHERE id =', \$e->{id});
    framework_ title => "Edit $title", dbobj => $e, tab => 'edit',
    sub {
        editmsg_ v => $e, "Edit $title";
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
    $data->{desc} = bb_subst_links $data->{desc};
    $data->{alias} =~ s/\n\n+/\n/;
    die "No title in original language" if !grep $_->{lang} eq $data->{olang}, $data->{titles}->@*;

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
