package VNWeb::Chars::Edit;

use VNWeb::Prelude;
use VNWeb::Images::Lib 'enrich_image';
use VNWeb::Releases::Lib;


my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    id         => { default => undef, vndbid => 'c' },
    name       => { sl => 1, maxlength => 200 },
    latin      => { default => undef, sl => 1, maxlength => 200 },
    alias      => { default => '', maxlength => 500 },
    description=> { default => '', maxlength => 5000 },
    sex        => { default => '', enum => \%CHAR_SEX },
    spoil_sex  => { default => sub { $_[0] }, enum => \%CHAR_SEX },
    gender     => { default => sub { $_[0] }, enum => \%CHAR_GENDER },
    spoil_gender=>{ default => sub { $_[0] }, enum => \%CHAR_GENDER },
    birthday   => { default => 0, uint => 1, regex => qr/^(0|([1-9]|1[012])([012][0-9]|3[012]))$/ },
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
    } },
    vns        => { sort_keys => ['vid', 'rid'], aoh => {
        vid     => { vndbid => 'v' },
        rid     => { vndbid => 'r', default => undef },
        spoil   => { uint => 1, range => [0,2] },
        role    => { enum => \%CHAR_ROLE },
    } },
    hidden     => { anybool => 1 },
    locked     => { anybool => 1 },

    editsum    => { editsum => 1 },
    vnstate    => { _when => 'out', aoh => {
        id      => { vndbid => 'v' },
        rels    => $VNWeb::Elm::apis{Releases}[0],
        prods   => { aoh => { id => { vndbid => 'p' }, title => {} } },
        title   => {},
    } },
};


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

    my %vns;
    $e->{vnstate} = [ map !$vns{$_->{vid}}++ ? {
        id => $_->{vid},
        rels => releases_by_vn($_->{vid}, charlink => 1),
        prods => VNWeb::VN::Lib::charproducers($_->{vid}),
    } : (), $e->{vns}->@* ];
    enrich_merge id => sql('SELECT id, title[1+1] FROM', vnt, 'v WHERE id IN'), $e->{vnstate};

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
        div_ widget(CharEdit => $FORM_OUT, $copy ? {%$e, id=>undef} : $e), '';
    };
};


TUWF::get qr{/$RE{vid}/addchar}, sub {
    return tuwf->resDenied if !can_edit c => undef;
    my $v = tuwf->dbRowi('SELECT id, title[1+1] AS title FROM', vnt, 'v WHERE NOT hidden AND id =', \tuwf->capture('id'));
    return tuwf->resNotFound if !$v->{id};

    my $e = elm_empty($FORM_OUT);
    $e->{vns} = [{ vid => $v->{id}, rid => undef, spoil => 0, role => 'primary' }];
    $e->{vnstate} = [{
        id => $v->{id},
        title => $v->{title},
        rels => releases_by_vn($v->{id}, charlink => 1),
        prods => VNWeb::VN::Lib::charproducers($v->{id}),
    }];

    framework_ title => 'Add character',
    sub {
        editmsg_ c => undef, 'Add character';
        div_ widget(CharEdit => $FORM_OUT, $e), '';
    };
};


js_api CharEdit => $FORM_IN, sub ($data,@) {
    my $new = !$data->{id};
    my $e = $new ? {} : db_entry $data->{id} or return tuwf->resNotFound;
    return tuwf->resDenied if !can_edit c => $e;

    if(!auth->permDbmod) {
        $data->{hidden} = $e->{hidden}||0;
        $data->{locked} = $e->{locked}||0;
    }
    $data->{description} = bb_subst_links $data->{description};

    $data->{spoil_sex} //= $data->{sex} if defined $data->{spoil_gender};
    my $sex = ($data->{sex}//'-').($data->{spoil_sex}//'-');
    my $gen = ($data->{gender}//'-').($data->{spoil_gender}//'-');
    ($data->{gender}, $data->{spoil_gender}) = (undef, undef) if $sex eq $gen;
    $data->{spoil_sex} = undef if !defined $data->{gender} && defined $data->{spoil_sex} && $data->{spoil_sex} eq $data->{sex};

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
    for($data->{vns}->@*) {
        return "Invalid release for $_->{vid}: $_->{rid}\n" if defined $_->{rid} && !tuwf->dbVali('
            SELECT 1
              FROM releases r
              JOIN releases_vn rv ON rv.id = r.id
             WHERE rv.id =', \$_->{rid}, 'AND rv.vid =', \$_->{vid}, "
               AND NOT r.hidden AND r.official AND rv.rtype <> 'trial'"
         );
    }

    my $ch = db_edit c => $e->{id}, $data;
    return 'No changes' if !$ch->{nitemid};
    +{ _redir => "/$ch->{nitemid}.$ch->{nrev}" };
};

1;
