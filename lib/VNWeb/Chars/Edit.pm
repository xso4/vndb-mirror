package VNWeb::Chars::Edit;

use VNWeb::Prelude;
use VNWeb::Images::Lib 'enrich_image';
use VNWeb::Releases::Lib;


my $FORM = {
    id         => { default => undef, vndbid => 'c' },
    name       => { maxlength => 200 },
    latin      => { default => undef, maxlength => 200 },
    alias      => { default => '', maxlength => 500 },
    description=> { default => '', maxlength => 5000 },
    gender     => { default => 'unknown', enum => \%GENDER },
    spoil_gender=>{ default => undef, enum => \%GENDER },
    b_month    => { default => 0, uint => 1, range => [ 0, 12 ] },
    b_day      => { default => 0, uint => 1, range => [ 0, 31 ] },
    age        => { default => undef, uint => 1, range => [ 0, 32767 ] },
    s_bust     => { default => 0, uint => 1, range => [ 0, 32767 ] },
    s_waist    => { default => 0, uint => 1, range => [ 0, 32767 ] },
    s_hip      => { default => 0, uint => 1, range => [ 0, 32767 ] },
    height     => { default => 0, uint => 1, range => [ 0, 32767 ] },
    weight     => { default => undef, uint => 1, range => [ 0, 32767 ] },
    bloodt     => { default => 'unknown', enum => \%BLOOD_TYPE },
    cup_size   => { default => '', enum => \%CUP_SIZE },
    main       => { default => undef, vndbid => 'c' },
    main_spoil => { uint => 1, range => [0,2] },
    main_ref   => { _when => 'out', anybool => 1 },
    main_name  => { _when => 'out', default => '' },
    image      => { default => undef, vndbid => 'ch' },
    image_info => { _when => 'out', default => undef, type => 'hash', keys => $VNWeb::Elm::apis{ImageResult}[0]{aoh} },
    traits     => { sort_keys => 'id', aoh => {
        tid     => { vndbid => 'i' },
        spoil   => { uint => 1, range => [0,2] },
        lie     => { anybool => 1 },
        name    => { _when => 'out' },
        group   => { _when => 'out', default => undef },
        hidden  => { _when => 'out', anybool => 1 },
        locked  => { _when => 'out', anybool => 1 },
        applicable => { _when => 'out', anybool => 1 },
        new     => { _when => 'out', anybool => 1 },
    } },
    vns        => { sort_keys => ['vid', 'rid'], aoh => {
        vid     => { vndbid => 'v' },
        rid     => { vndbid => 'r', default => undef },
        spoil   => { uint => 1, range => [0,2] },
        role    => { enum => \%CHAR_ROLE },
        title   => { _when => 'out' },
    } },
    hidden     => { anybool => 1 },
    locked     => { anybool => 1 },

    authmod    => { _when => 'out', anybool => 1 },
    editsum    => { _when => 'in out', editsum => 1 },
    releases   => { _when => 'out', aoh => {
        id      => { vndbid => 'r' },
        rels    => $VNWeb::Elm::apis{Releases}[0]
    } },
};

my $FORM_OUT = form_compile out => $FORM;
my $FORM_IN  = form_compile in  => $FORM;
my $FORM_CMP = form_compile cmp => $FORM;


TUWF::get qr{/$RE{crev}/(?<action>edit|copy)} => sub {
    my $e = db_entry tuwf->captures('id', 'rev') or return tuwf->resNotFound;
    my $copy = tuwf->capture('action') eq 'copy';
    return tuwf->resDenied if !can_edit c => $copy ? {} : $e;

    $e->{main_name} = $e->{main} ? tuwf->dbVali('SELECT title[1+1] FROM', charst, 'c WHERE id =', \$e->{main}) : '';
    $e->{main_ref} = tuwf->dbVali('SELECT 1 FROM chars WHERE main =', \$e->{id})||0;

    enrich_merge tid => sql(
        'SELECT t.id AS tid, t.name, t.hidden, t.locked, t.applicable, g.name AS group, g.gorder AS order, false AS new
           FROM traits t
           LEFT JOIN traits g ON g.id = t.gid
          WHERE', $copy ? 'NOT t.hidden AND t.applicable AND' : (), 't.id IN'), $e->{traits};
    $e->{traits} = [ sort { ($a->{order}//99) <=> ($b->{order}//99) || $a->{name} cmp $b->{name} } grep !$copy || $_->{applicable}, $e->{traits}->@* ];

    enrich_merge vid => sql('SELECT id AS vid, title[1+1] AS title, sorttitle FROM', vnt, 'v WHERE id IN'), $e->{vns};
    $e->{vns} = [ sort { $a->{sorttitle} cmp $b->{sorttitle} || idcmp($a->{vid}, $b->{vid}) || idcmp($a->{rid}||'r0', $b->{rid}||'r0') } $e->{vns}->@* ];

    my %vns;
    $e->{releases} = [ map !$vns{$_->{vid}}++ ? { id => $_->{vid}, rels => releases_by_vn $_->{vid} } : (), $e->{vns}->@* ];

    if($e->{image}) {
        $e->{image_info} = { id => $e->{image} };
        enrich_image 0, [$e->{image_info}];
    } else {
        $e->{image_info} = undef;
    }

    $e->{authmod} = auth->permDbmod;
    $e->{editsum} = $copy ? "Copied from $e->{id}.$e->{chrev}" : $e->{chrev} == $e->{maxrev} ? '' : "Reverted to revision $e->{id}.$e->{chrev}";

    my $title = ($copy ? 'Copy ' : 'Edit ').dbobj($e->{id})->{title}[1];
    framework_ title => $title, dbobj => $e, tab => tuwf->capture('action'),
    sub {
        editmsg_ c => $e, $title, $copy;
        elm_ CharEdit => $FORM_OUT, $copy ? {%$e, id=>undef} : $e;
    };
};


TUWF::get qr{/$RE{vid}/addchar}, sub {
    return tuwf->resDenied if !can_edit c => undef;
    my $v = tuwf->dbRowi('SELECT id, title[1+1] AS title FROM', vnt, 'v WHERE NOT hidden AND id =', \tuwf->capture('id'));
    return tuwf->resNotFound if !$v->{id};

    my $e = elm_empty($FORM_OUT);
    $e->{vns} = [{ vid => $v->{id}, title => $v->{title}, rid => undef, spoil => 0, role => 'primary' }];
    $e->{releases} = [{ id => $v->{id}, rels => releases_by_vn $v->{id} }];

    framework_ title => 'Add character',
    sub {
        editmsg_ c => undef, 'Add character';
        elm_ CharEdit => $FORM_OUT, $e;
    };
};


elm_api CharEdit => $FORM_OUT, $FORM_IN, sub {
    my $data = shift;
    my $new = !$data->{id};
    my $e = $new ? {} : db_entry $data->{id} or return tuwf->resNotFound;
    return elm_Unauth if !can_edit c => $e;

    if(!auth->permDbmod) {
        $data->{hidden} = $e->{hidden}||0;
        $data->{locked} = $e->{locked}||0;
    }
    $data->{description} = bb_subst_links $data->{description};
    $data->{b_day} = 0 if !$data->{b_month};

    $data->{main} = undef if $data->{hidden};
    die "Attempt to set main to self" if $data->{main} && $e->{id} && $data->{main} eq $e->{id};
    die "Attempt to set main while this character is already referenced." if $data->{main} && tuwf->dbVali('SELECT 1 AS ref FROM chars WHERE main =', \$e->{id});
    # It's possible that the referenced character has been deleted since it was added as main, so don't die() on this one, just unset main.
    $data->{main} = undef if $data->{main} && !tuwf->dbVali('SELECT 1 FROM chars WHERE NOT hidden AND main IS NULL AND id =', \$data->{main});
    $data->{main_spoil} = 0 if !$data->{main};

    validate_dbid 'SELECT id FROM images WHERE id IN', $data->{image} if $data->{image};

    # Allow non-applicable or non-approved traits only when they were already applied to this character.
    validate_dbid
        sql('SELECT id FROM traits t WHERE ((NOT hidden AND applicable) OR EXISTS(SELECT 1 FROM chars_traits ct WHERE ct.tid = t.id AND ct.id =', \$e->{id}, ')) AND id IN'),
        map $_->{tid}, $data->{traits}->@*;

    validate_dbid 'SELECT id FROM vn WHERE id IN', map $_->{vid}, $data->{vns}->@*;
    # XXX: This will also die when the release has been moved to a different VN
    # and the char hasn't been updated yet. Would be nice to give a better
    # error message in that case.
    for($data->{vns}->@*) {
        die "Bad release for $_->{vid}: $_->{rid}\n" if defined $_->{rid} && !tuwf->dbVali('SELECT 1 FROM releases_vn WHERE id =', \$_->{rid}, 'AND vid =', \$_->{vid});
    }

    return elm_Unchanged if !$new && !form_changed $FORM_CMP, $data, $e;
    my $ch = db_edit c => $e->{id}, $data;
    elm_Redirect "/$ch->{nitemid}.$ch->{nrev}";
};

1;
