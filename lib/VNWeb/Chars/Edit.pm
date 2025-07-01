package VNWeb::Chars::Edit;

use VNWeb::Prelude;
use VNWeb::Images::Lib 'enrich_image', '$IMGSCHEMA';
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
    image_info => { _when => 'out', default => undef, type => 'hash', keys => $IMGSCHEMA },
    traits     => { sort_keys => 'tid', aoh => {
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
    maxrev     => { default => undef, uint => 1 },
    vnstate    => { _when => 'out', aoh => {
        id      => { vndbid => 'v' },
        rels    => { aoh => $RELSCHEMA },
        prods   => { aoh => { id => { vndbid => 'p' }, title => {} } },
        title   => {},
    } },
};


FU::get qr{/$RE{crev}/(edit|copy)} => sub($id, $rev, $action) {
    my $e = db_entry $id, $rev or fu->notfound;
    my $copy = $action eq 'copy';
    fu->denied if !can_edit c => $copy ? {} : $e;

    $e->{main_name} = $e->{main} ? fu->SQL('SELECT title[2] FROM', CHARST, 'c WHERE id =', $e->{main})->val : '';
    $e->{main_ref} = !!fu->SQL('SELECT 1 FROM chars WHERE main =', $e->{id}, 'LIMIT 1')->val;

    fu->enrich(merge => 1, key => 'tid', SQL(
        'SELECT t.id AS tid, t.name, t.hidden, t.locked, t.applicable, g.name AS group, g.gorder AS order, false AS new
           FROM traits t
           LEFT JOIN traits g ON g.id = t.gid
          WHERE', $copy ? 'NOT t.hidden AND t.applicable AND' : (), 't.id'
    ), $e->{traits});
    $e->{traits} = [ sort { ($a->{order}//99) <=> ($b->{order}//99) || $a->{name} cmp $b->{name} } grep !$copy || $_->{applicable}, $e->{traits}->@* ];

    my %vns;
    $e->{vnstate} = [ map !$vns{$_->{vid}}++ ? {
        id => $_->{vid},
        rels => releases_by_vn($_->{vid}, charlink => 1),
        prods => VNWeb::VN::Lib::charproducers($_->{vid}),
    } : (), $e->{vns}->@* ];
    fu->enrich(set => 'title', SQL('SELECT id, title[2] FROM', VNT, 'WHERE id'), $e->{vnstate});

    if($e->{image}) {
        $e->{image_info} = { id => $e->{image} };
        enrich_image 0, [$e->{image_info}];
    } else {
        $e->{image_info} = undef;
    }

    $e->{authmod} = auth->permDbmod;
    $e->{editsum} = $copy ? "Copied from $e->{id}.$e->{chrev}" : $e->{chrev} == $e->{maxrev} ? '' : "Reverted to revision $e->{id}.$e->{chrev}";

    my $title = ($copy ? 'Copy ' : 'Edit ').dbobj($e->{id})->{title}[1];
    framework_ title => $title, dbobj => $e, tab => $action,
    sub {
        editmsg_ c => $e, $title, $copy;
        div_ widget(CharEdit => $FORM_OUT, $copy ? {%$e, id=>undef} : $e), '';
    };
};


FU::get qr{/$RE{vid}/addchar}, sub($vid) {
    fu->denied if !can_edit c => undef;
    my $title = fu->SQL('SELECT title[2] FROM', VNT, 'WHERE NOT hidden AND id =', $vid)->val;
    fu->notfound if !length $title;

    my $e = $FORM_OUT->empty;
    $e->{vns} = [{ vid => $vid, rid => undef, spoil => 0, role => 'primary' }];
    $e->{vnstate} = [{
        id => $vid,
        title => $title,
        rels => releases_by_vn($vid, charlink => 1),
        prods => VNWeb::VN::Lib::charproducers($vid),
    }];

    framework_ title => 'Add character',
    sub {
        editmsg_ c => undef, 'Add character';
        div_ widget(CharEdit => $FORM_OUT, $e), '';
    };
};


js_api CharEdit => $FORM_IN, sub ($data,@) {
    my $new = !$data->{id};
    my $e = $new ? {} : db_entry $data->{id} or fu->notfound;
    fu->denied if !can_edit c => $e;

    validate_maxrev $data, $e;
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
    return '"Instance" should not point to the same character' if $data->{main} && $e->{id} && $data->{main} eq $e->{id};
    return 'Attempt to set instance while this character is already referenced from another character.'
        if $data->{main} && fu->SQL('SELECT 1 FROM chars WHERE main =', $e->{id}, 'LIMIT 1')->val;
    # It's possible that the referenced character has been deleted since it was added as main, so don't die() on this one, just unset main.
    $data->{main} = undef if $data->{main} && !fu->SQL('SELECT 1 FROM chars WHERE NOT hidden AND main IS NULL AND id =', $data->{main})->val;
    $data->{main_spoil} = 0 if !$data->{main};

    validate_dbid 'SELECT id FROM images WHERE id', $data->{image} if $data->{image};

    # Allow non-applicable or non-approved traits only when they were already applied to this character.
    validate_dbid
        SQL('SELECT id FROM traits t WHERE ((NOT hidden AND applicable) OR EXISTS(SELECT 1 FROM chars_traits ct WHERE ct.tid = t.id AND ct.id =', $e->{id}, ')) AND id'),
        map $_->{tid}, $data->{traits}->@*;

    validate_dbid 'SELECT id FROM vn WHERE id', map $_->{vid}, $data->{vns}->@*;
    for($data->{vns}->@*) {
        return "Invalid release for $_->{vid}: $_->{rid}\n" if defined $_->{rid} && !fu->SQL('
            SELECT 1
              FROM releases r
              JOIN releases_vn rv ON rv.id = r.id
             WHERE rv.id =', $_->{rid}, 'AND rv.vid =', $_->{vid}, "
               AND NOT r.hidden AND r.official AND rv.rtype <> 'trial'
             LIMIT 1"
        )->val;
    }

    my $ch = db_edit c => $e->{id}, $data;
    return 'No changes' if !$ch->{nitemid};
    +{ _redir => "/$ch->{nitemid}.$ch->{nrev}" };
};

1;
