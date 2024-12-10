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
    gender     => { default => '', enum => \%STAFF_GENDER },
    lang       => { language => 1 },
    extlinks   => { extlinks => 's' },
    hidden     => { anybool => 1 },
    locked     => { anybool => 1 },
    editsum    => { editsum => 1 },
};


TUWF::get qr{/$RE{srev}/edit} => sub {
    my $e = db_entry tuwf->captures('id', 'rev') or return tuwf->resNotFound;
    return tuwf->resDenied if !can_edit s => $e;

    $e->{editsum} = $e->{chrev} == $e->{maxrev} ? '' : "Reverted to revision $e->{id}.$e->{chrev}";

    my $alias_inuse = 'EXISTS(SELECT 1 FROM vn_staff WHERE aid = sa.aid UNION ALL SELECT 1 FROM vn_seiyuu WHERE aid = sa.aid)';
    enrich_merge aid => sub { "SELECT aid, $alias_inuse AS inuse, false AS wantdel FROM unnest(", sql_array(@$_), '::int[]) AS sa(aid)' }, $e->{alias};

    # If we're reverting to an older revision, we have to make sure all the
    # still referenced aliases are included.
    push $e->{alias}->@*, tuwf->dbAlli(
        "SELECT aid, name, latin, true AS inuse, true AS wantdel
           FROM staff_alias sa WHERE $alias_inuse AND sa.id =", \$e->{id}, 'AND sa.aid NOT IN', [ map $_->{aid}, $e->{alias}->@* ]
    )->@* if $e->{chrev} != $e->{maxrev};

    $e->{alias} = [ sort { ($a->{latin}//$a->{name}) cmp ($b->{latin}//$b->{name}) } $e->{alias}->@* ];
    VNDB::ExtLinks::enrich $e;

    my $name = titleprefs_swap($e->{lang}, @{ (grep $_->{aid} == $e->{main}, @{$e->{alias}})[0] }{qw/ name latin /})->[1];
    framework_ title => "Edit $name", dbobj => $e, tab => 'edit',
    sub {
        editmsg_ s => $e, "Edit $name";
        div_ widget(StaffEdit => $FORM_OUT, $e), '';
    };
};


TUWF::get qr{/s/new}, sub {
    return tuwf->resDenied if !can_edit s => undef;
    framework_ title => 'Add staff member',
    sub {
        editmsg_ s => undef, 'Add staff member';
        div_ widget(StaffEdit => $FORM_OUT, {
            elm_empty($FORM_OUT)->%*,
            alias => [ { aid => -1, name => '', latin => undef, inuse => 0, wantdel => 0 } ],
            main => -1
        }), '';
    };
};


js_api StaffEdit => $FORM_IN, sub {
    my $data = shift;
    my $new = !$data->{id};
    my $e = $new ? { id => 0 } : db_entry $data->{id} or return tuwf->resNotFound;
    return tuwf->resDenied if !can_edit s => $e;

    if(!auth->permDbmod) {
        $data->{hidden} = $e->{hidden}||0;
        $data->{locked} = $e->{locked}||0;
    }
    $data->{l_wp} = $e->{l_wp}||'';
    $data->{description} = bb_subst_links $data->{description};

    # The form validation only checks for duplicate aid's, but the name+latin should also be unique.
    my %names;
    die "Duplicate aliases" if grep $names{"$_->{name}\x00".($_->{latin}//'')}++, $data->{alias}->@*;
    die "Latin = name" if grep $_->{latin} && $_->{name} eq $_->{latin}, $data->{alias}->@*;

    # For positive alias IDs: Make sure they exist and are (or were) owned by this entry.
    validate_dbid
        sql('SELECT aid FROM staff_alias_hist WHERE chid IN(SELECT id FROM changes WHERE itemid =', \$e->{id}, ') AND aid IN'),
        grep $_>=0, map $_->{aid}, $data->{alias}->@*;

    # For negative alias IDs: Assign a new ID.
    for my $alias (grep $_->{aid} < 0, $data->{alias}->@*) {
        my $new = tuwf->dbVali(select => sql_func nextval => \'staff_alias_aid_seq');
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
