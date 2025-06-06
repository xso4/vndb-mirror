package VNWeb::Staff::Edit;

use VNWeb::Prelude;


my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    id          => { default => undef, vndbid => 's' },
    main        => { int => 1, range => [ -1000, 1<<40 ] }, # X
    alias       => { maxlength => 100, sort_keys => 'aid', aoh => {
        aid       => { int => 1, range => [ -1000, 1<<40 ] }, # X, negative IDs are for new aliases
        name      => { sl => 1, maxlength => 200 },
        latin     => { sl => 1, maxlength => 200, default => undef },
        inuse     => { anybool => 1, _when => 'out' },
        wantdel   => { anybool => 1, _when => 'out' },
    } },
    description=> { default => '', maxlength => 5000 },
    stype      => { default => 'person', enum => \%STAFF_TYPE },
    gender     => { default => '', enum => \%STAFF_GENDER },
    lang       => { language => 1 },
    prod       => { default => undef, vndbid => 'p' },
    prod_title => { _when => 'out', default => undef, type => 'array' },
    extlinks   => { extlinks => 's' },
    hidden     => { anybool => 1 },
    locked     => { anybool => 1 },
    editsum    => { editsum => 1 },
};


FU::get qr{/$RE{srev}/edit} => sub($id, $rev=0) {
    my $e = db_entry $id, $rev or return fu->notfound;
    return fu->denied if !can_edit s => $e;

    $e->{editsum} = $e->{chrev} == $e->{maxrev} ? '' : "Reverted to revision $e->{id}.$e->{chrev}";

    my $alias_inuse = RAW 'EXISTS(SELECT 1 FROM vn_staff WHERE aid = sa.aid UNION ALL SELECT 1 FROM vn_seiyuu WHERE aid = sa.aid)';
    fu->enrich(merge => 1, key => 'aid', sub { SQL 'SELECT aid, ', $alias_inuse, 'AS inuse, false AS wantdel FROM unnest(', $_, '::int[]) AS sa(aid)' }, $e->{alias});

    $e->{prod_title} = fu->SQL('SELECT title FROM', PRODUCERST, 'WHERE id =', $e->{prod})->val if $e->{prod};

    # If we're reverting to an older revision, we have to make sure all the
    # still referenced aliases are included.
    push $e->{alias}->@*, fu->SQL(
        'SELECT aid, name, latin, true AS inuse, true AS wantdel
           FROM staff_alias sa WHERE', $alias_inuse, 'AND sa.id =', $e->{id}, 'AND NOT sa.aid', IN [ map $_->{aid}, $e->{alias}->@* ]
    )->allh->@* if $e->{chrev} != $e->{maxrev};

    $e->{alias} = [ sort { ($a->{latin}//$a->{name}) cmp ($b->{latin}//$b->{name}) } $e->{alias}->@* ];

    my $name = titleprefs_swap($e->{lang}, @{ (grep $_->{aid} == $e->{main}, @{$e->{alias}})[0] }{qw/ name latin /})->[1];
    framework_ title => "Edit $name", dbobj => $e, tab => 'edit',
    sub {
        editmsg_ s => $e, "Edit $name";
        div_ widget(StaffEdit => $FORM_OUT, $e), '';
    };
};


FU::get '/s/new', sub {
    fu->denied if !can_edit s => undef;
    framework_ title => 'Add staff member',
    sub {
        editmsg_ s => undef, 'Add staff member';
        div_ widget(StaffEdit => $FORM_OUT, {
            $FORM_OUT->empty->%*,
            alias => [ { aid => -1, name => '', latin => undef, inuse => 0, wantdel => 0 } ],
            main => -1
        }), '';
    };
};


js_api StaffEdit => $FORM_IN, sub {
    my $data = shift;
    my $new = !$data->{id};
    my $e = $new ? { id => 0 } : db_entry $data->{id} or fu->notfound;
    fu->denied if !can_edit s => $e;

    if(!auth->permDbmod) {
        $data->{hidden} = $e->{hidden}||0;
        $data->{locked} = $e->{locked}||0;
    }
    $data->{gender} = '' if $data->{stype} ne 'person';
    $data->{description} = bb_subst_links $data->{description};

    if ($data->{prod}) {
        return "Producer ($data->{prod}) is already linked to another staff entry."
            if fu->SQL('SELECT 1 FROM staff WHERE NOT hidden AND prod =', $data->{prod}, $new ? () : ('AND id <>', $e->{id}), 'LIMIT 1')->val;
        validate_dbid 'SELECT id FROM producers WHERE NOT hidden AND id', $data->{prod};
    }

    # The form validation only checks for duplicate aid's, but the name+latin should also be unique.
    my %names;
    die "Duplicate aliases" if grep $names{"$_->{name}\x00".($_->{latin}//'')}++, $data->{alias}->@*;
    die "Latin = name" if grep $_->{latin} && $_->{name} eq $_->{latin}, $data->{alias}->@*;

    # For positive alias IDs: Make sure they exist and are (or were) owned by this entry.
    validate_dbid
        SQL('SELECT aid FROM staff_alias_hist WHERE chid IN(SELECT id FROM changes WHERE itemid =', $e->{id}, ') AND aid'),
        grep $_>=0, map $_->{aid}, $data->{alias}->@*;

    # For negative alias IDs: Assign a new ID.
    for my $alias (grep $_->{aid} < 0, $data->{alias}->@*) {
        my $new = fu->sql("SELECT nextval('staff_alias_aid_seq')")->val;
        $data->{main} = $new if $alias->{aid} == $data->{main};
        $alias->{aid} = $new;
    }
    # We rely on Postgres to throw an error if we attempt to delete an alias that is still being referenced.

    VNDB::ExtLinks::normalize $e, $data;

    my $ch = db_edit s => $e->{id}, $data;
    return 'No changes.' if !$ch->{nitemid};
    +{ _redir => "/$ch->{nitemid}.$ch->{nrev}" };
};

1;
