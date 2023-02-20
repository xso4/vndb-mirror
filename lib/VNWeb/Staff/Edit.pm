package VNWeb::Staff::Edit;

use VNWeb::Prelude;


my $FORM = {
    id          => { required => 0, vndbid => 's' },
    aid         => { int => 1, range => [ -1000, 1<<40 ] }, # X
    alias       => { maxlength => 100, sort_keys => 'aid', aoh => {
        aid       => { int => 1, range => [ -1000, 1<<40 ] }, # X, negative IDs are for new aliases
        name      => { maxlength => 200 },
        original  => { maxlength => 200, required => 0 },
        inuse     => { anybool => 1, _when => 'out' },
        wantdel   => { anybool => 1, _when => 'out' },
    } },
    desc       => { required => 0, default => '', maxlength => 5000 },
    gender     => { default => 'unknown', enum => [qw[unknown m f]] },
    lang       => { default => 'ja', language => 1 },
    l_site     => { required => 0, default => '', weburl => 1 },
    l_wikidata => { required => 0, uint => 1, max => (1<<31)-1 },
    l_twitter  => { required => 0, default => '', regex => qr/^\S+$/, maxlength => 16 },
    l_anidb    => { required => 0, uint => 1, max => (1<<31)-1, default => undef },
    l_pixiv    => { required => 0, uint => 1, max => (1<<31)-1, default => 0 },
    hidden     => { anybool => 1 },
    locked     => { anybool => 1 },

    authmod    => { _when => 'out', anybool => 1 },
    editsum    => { _when => 'in out', editsum => 1 },
};

my $FORM_OUT = form_compile out => $FORM;
my $FORM_IN  = form_compile in  => $FORM;
my $FORM_CMP = form_compile cmp => $FORM;


TUWF::get qr{/$RE{srev}/edit} => sub {
    my $e = db_entry tuwf->captures('id', 'rev') or return tuwf->resNotFound;
    return tuwf->resDenied if !can_edit s => $e;

    $e->{authmod} = auth->permDbmod;
    $e->{editsum} = $e->{chrev} == $e->{maxrev} ? '' : "Reverted to revision $e->{id}.$e->{chrev}";

    my $alias_inuse = 'EXISTS(SELECT 1 FROM vn_staff WHERE aid = sa.aid UNION ALL SELECT 1 FROM vn_seiyuu WHERE aid = sa.aid)';
    enrich_merge aid => sub { "SELECT aid, $alias_inuse AS inuse, false AS wantdel FROM unnest(", sql_array(@$_), '::int[]) AS sa(aid)' }, $e->{alias};

    # If we're reverting to an older revision, we have to make sure all the
    # still referenced aliases are included.
    push $e->{alias}->@*, tuwf->dbAlli(
        "SELECT aid, name, original, true AS inuse, true AS wantdel
           FROM staff_alias sa WHERE $alias_inuse AND sa.id =", \$e->{id}, 'AND sa.aid NOT IN', [ map $_->{aid}, $e->{alias}->@* ]
    )->@* if $e->{chrev} != $e->{maxrev};

    my $name = (grep $_->{aid} == $e->{aid}, @{$e->{alias}})[0]{name};
    framework_ title => "Edit $name", dbobj => $e, tab => 'edit',
    sub {
        editmsg_ s => $e, "Edit $name";
        elm_ StaffEdit => $FORM_OUT, $e;
    };
};


TUWF::get qr{/s/new}, sub {
    return tuwf->resDenied if !can_edit s => undef;
    framework_ title => 'Add staff member',
    sub {
        editmsg_ s => undef, 'Add staff member';
        elm_ StaffEdit => $FORM_OUT, {
            elm_empty($FORM_OUT)->%*,
            alias => [ { aid => -1, name => '', original => undef, inuse => 0, wantdel => 0 } ],
            aid => -1
        };
    };
};


elm_api StaffEdit => $FORM_OUT, $FORM_IN, sub {
    my $data = shift;
    my $new = !$data->{id};
    my $e = $new ? { id => 0 } : db_entry $data->{id} or return tuwf->resNotFound;
    return elm_Unauth if !can_edit s => $e;

    if(!auth->permDbmod) {
        $data->{hidden} = $e->{hidden}||0;
        $data->{locked} = $e->{locked}||0;
    }
    $data->{l_wp} = $e->{l_wp}||'';
    $data->{desc} = bb_subst_links $data->{desc};

    # The form validation only checks for duplicate aid's, but the name+original should also be unique.
    my %names;
    die "Duplicate aliases" if grep $names{"$_->{name}\x00".($_->{original}//'')}++, $data->{alias}->@*;
    die "Original = name" if grep $_->{original} && $_->{name} eq $_->{original}, $data->{alias}->@*;

    # For positive alias IDs: Make sure they exist and are (or were) owned by this entry.
    validate_dbid
        sql('SELECT aid FROM staff_alias_hist WHERE chid IN(SELECT id FROM changes WHERE itemid =', \$e->{id}, ') AND aid IN'),
        grep $_>=0, map $_->{aid}, $data->{alias}->@*;

    # For negative alias IDs: Assign a new ID.
    for my $alias (grep $_->{aid} < 0, $data->{alias}->@*) {
        my $new = tuwf->dbVali(select => sql_func nextval => \'staff_alias_aid_seq');
        $data->{aid} = $new if $alias->{aid} == $data->{aid};
        $alias->{aid} = $new;
    }
    # We rely on Postgres to throw an error if we attempt to delete an alias that is still being referenced.

    return elm_Unchanged if !$new && !form_changed $FORM_CMP, $data, $e;
    my $ch = db_edit s => $e->{id}, $data;
    elm_Redirect "/$ch->{nitemid}.$ch->{nrev}";
};

1;
