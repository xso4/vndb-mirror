package VNWeb::VN::Edit;

use VNWeb::Prelude;
use VNWeb::Images::Lib 'enrich_image', '$IMGSCHEMA';
use VNWeb::Releases::Lib;


my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    id         => { default => undef, vndbid => 'v' },
    titles     => { minlength => 1, sort_keys => 'lang', aoh => {
        lang     => { enum => \%LANGUAGE },
        title    => { sl => 1, maxlength => 250 },
        latin    => { default => undef, sl => 1, maxlength => 250 },
        official => { anybool => 1 },
    } },
    alias      => { default => '', maxlength => 500 },
    description=> { default => '', maxlength => 10240 },
    devstatus  => { uint => 1, enum => \%DEVSTATUS },
    olang      => { default => 'ja', enum => \%LANGUAGE },
    length     => { uint => 1, enum => \%VN_LENGTH },
    l_wikidata => { default => undef, uint => 1, max => (1<<31)-1 },
    l_renai    => { default => '', sl => 1, maxlength => 100 },
    relations  => { sort_keys => 'vid', aoh => {
        vid      => { vndbid => 'v' },
        relation => { enum => \%VN_RELATION },
        official => { anybool => 1 },
        title    => { _when => 'out' },
    } },
    anime      => { sort_keys => 'aid', aoh => {
        aid          => { id => 1 },
        title_romaji => { _when => 'out' },
        title_kanji  => { _when => 'out', default => '' },
    } },
    editions   => { sort_keys => 'eid', aoh => {
        eid      => { uint => 1, max => 500 },
        lang     => { default => undef, language => 1 },
        name     => { sl => 1, maxlength => 150 },
        official => { anybool => 1 },
    } },
    staff      => { sort_keys => ['aid','eid','role'], aoh => {
        aid      => { id => 1 },
        eid      => { default => undef, uint => 1 },
        role     => { enum => \%CREDIT_TYPE },
        note     => { default => '', sl => 1, maxlength => 250 },
        sid      => { _when => 'out', vndbid => 's' },
        title    => { _when => 'out' },
        alttitle => { _when => 'out' },
    } },
    seiyuu     => { sort_keys => ['aid','cid'], aoh => {
        aid      => { id => 1 },
        cid      => { vndbid => 'c' },
        note     => { default => '', sl => 1, maxlength => 250 },
        # Staff info
        sid      => { _when => 'out', vndbid => 's' },
        title    => { _when => 'out' },
        alttitle => { _when => 'out' },
    } },
    screenshots=> { sort_keys => 'scr', aoh => {
        scr      => { vndbid => 'sf' },
        rid      => { default => undef, vndbid => 'r' },
        info     => { _when => 'out', type => 'hash', keys => $IMGSCHEMA },
    } },
    hidden     => { anybool => 1 },
    locked     => { anybool => 1 },

    editsum    => { editsum => 1 },
    maxrev     => { default => undef, uint => 1 },
    releases   => { _when => 'out', aoh => $RELSCHEMA },
    reltitles  => { _when => 'out', elems => {} },
    chars      => { _when => 'out', aoh => {
        id       => { vndbid => 'c' },
        title    => {},
        alttitle => {},
    } },
};


FU::get qr{/$RE{vrev}/edit} => sub($id, $rev=0) {
    my $e = db_entry $id, $rev or fu->notfound;
    fu->denied if !can_edit v => $e;

    $e->{editsum} = $e->{chrev} == $e->{maxrev} ? '' : "Reverted to revision $e->{id}.$e->{chrev}";

    $_->{info} = {id=>$_->{scr}} for $e->{screenshots}->@*;
    enrich_image 0, [map $_->{info}, $e->{screenshots}->@*];

    $_->{title} = $_->{title}[1] for $e->{relations}->@*;
    ($_->{title}, $_->{alttitle}) = ($_->{title}[1], $_->{title}[3]) for ($e->{staff}->@*, $e->{seiyuu}->@*);

    # It's possible for older revisions to link to aliases that have been removed.
    # Let's exclude those to make sure the form will at least load.
    $e->{staff}  = [ grep $_->{sid}, $e->{staff}->@* ];
    $e->{seiyuu} = [ grep $_->{sid}, $e->{seiyuu}->@* ];

    $e->{releases} = releases_by_vn $e->{id};
    $e->{reltitles} = fu->SQL('
        SELECT DISTINCT lower(i.title)
          FROM releases r
          JOIN releases_vn rv ON rv.id = r.id
          JOIN releases_titles rt ON rt.id = r.id
          JOIN unnest(ARRAY[rt.title,rt.latin]) i(title) ON i.title IS NOT NULL
         WHERE NOT r.hidden AND rv.vid =', $e->{id}
    )->flat;

    $e->{chars} = fu->SQL('
        SELECT id, title[2], title[4] AS alttitle FROM', CHARST, '
         WHERE NOT hidden AND id IN(SELECT id FROM chars_vns WHERE vid =', $e->{id},')
         ORDER BY sorttitle, id'
    )->allh;

    my $title = titleprefs_obj $e->{olang}, $e->{titles};
    framework_ title => "Edit $title->[1]", dbobj => $e, tab => 'edit',
    sub {
        editmsg_ v => $e, "Edit $title->[1]";
        div_ widget(VNEdit => $FORM_OUT, $e), '';
    };
};


FU::get '/v/add', sub {
    fu->denied if !can_edit v => undef;

    framework_ title => 'Add visual novel',
    sub {
        editmsg_ v => undef, 'Add visual novel';
        div_ widget(VNEdit => $FORM_OUT, $FORM_OUT->empty), '';
    };
};


js_api VNEdit => $FORM_IN, sub($data) {
    my $new = !$data->{id};
    my $e = $new ? { id => 0 } : db_entry $data->{id} or fu->notfound;
    fu->denied if !can_edit v => $e;

    validate_maxrev $data, $e;
    if(!auth->permDbmod) {
        $data->{hidden} = $e->{hidden}||0;
        $data->{locked} = $e->{locked}||0;
    }
    $data->{description} = bb_subst_links $data->{description};
    $data->{alias} =~ s/\n\n+/\n/;

    my($otitle) = grep $_->{lang} eq $data->{olang}, $data->{titles}->@*;
    return 'No title for the original language' if !$otitle;
    $otitle->{official} = 1;

    $data->{length} = 0 if $data->{devstatus} == 1;

    # Prevent staff aliases from being "referenced" by deleted VNs.
    $data->{staff} = $data->{seiyuu} = [] if $data->{hidden};

    validate_dbid 'SELECT id FROM anime WHERE id', map $_->{aid}, $data->{anime}->@*;
    validate_dbid 'SELECT id FROM images WHERE id', map $_->{scr}, $data->{screenshots}->@*;
    validate_dbid 'SELECT aid FROM staff_alias WHERE aid', map $_->{aid}, $data->{staff}->@*;
    validate_dbid 'SELECT aid FROM staff_alias WHERE aid', map $_->{aid}, $data->{seiyuu}->@*;

    # Drop unused staff editions
    my %editions = map defined $_->{eid} ? +($_->{eid},1) : (), $data->{staff}->@*;
    $data->{editions} = [ grep $editions{$_->{eid}}, $data->{editions}->@* ];

    $data->{relations} = [] if $data->{hidden};
    validate_dbid 'SELECT id FROM vn WHERE id', map $_->{vid}, $data->{relations}->@*;
    return 'Invalid relation with self' if grep $_->{vid} eq $e->{id}, $data->{relations}->@*;

    return 'Screenshot without releases assigned' if grep !$_->{rid}, $data->{screenshots}->@*; # This is only the case for *very* old revisions, form disallows this now.
    # Allow linking to deleted or moved releases only if the previous revision also had that.
    # (The form really should encourage the user to fix that, but disallowing the edit seems a bit overkill)
    validate_dbid sub { SQL '
        SELECT r.id FROM releases r JOIN releases_vn rv ON r.id = rv.id WHERE NOT r.hidden AND rv.vid =', $e->{id}, ' AND r.id', IN $_, '
         UNION
        SELECT rid FROM vn_screenshots WHERE id =', $e->{id}, 'AND rid', IN $_
    }, map $_->{rid}, $data->{screenshots}->@*;

    # Likewise, allow linking to deleted or moved characters.
    validate_dbid sub { SQL '
        SELECT c.id FROM chars c JOIN chars_vns cv ON c.id = cv.id WHERE NOT c.hidden AND cv.vid =', $e->{id}, ' AND c.id', IN $_, '
         UNION
        SELECT cid FROM vn_seiyuu WHERE id =', $e->{id}, 'AND cid', IN $_
    }, map $_->{cid}, $data->{seiyuu}->@*;

    $data->{image_nsfw} = $e->{image_nsfw}||0;
    $data->{image} = $e->{image}||undef;
    my %oldscr = map +($_->{scr}, $_->{nsfw}), @{ $e->{screenshots}||[] };
    $_->{nsfw} = $oldscr{$_->{scr}}||0 for $data->{screenshots}->@*;

    my $ch = db_edit v => $e->{id}, $data;
    return 'No changes' if !$ch->{nitemid};
    update_reverse($ch->{nitemid}, $ch->{nrev}, $e, $data);
    +{ _redir => "/$ch->{nitemid}.$ch->{nrev}" };
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
