package VNWeb::TT::TraitEdit;

use VNWeb::Prelude;

my $FORM = {
    id           => { required => 0, id => 1 },
    name         => { maxlength => 250, regex => qr/^[^,\r\n]+$/ },
    alias        => { maxlength => 1024, regex => qr/^[^,]+$/, required => 0, default => '' },
    state        => { uint => 1, range => [0,2] },
    sexual       => { anybool => 1 },
    description  => { maxlength => 10240 },
    searchable   => { anybool => 1, default => 1 },
    applicable   => { anybool => 1, default => 1 },
    defaultspoil => { uint => 1, range => [0,2] },
    parents      => { aoh => {
        id          => { id => 1 },
        name        => { _when => 'out' },
        group       => { _when => 'out', required => 0 },
    } },
    order        => { uint => 1 },

    addedby      => { _when => 'out' },
    can_mod      => { _when => 'out', anybool => 1 },
};

my $FORM_OUT = form_compile out => $FORM;
my $FORM_IN  = form_compile in  => $FORM;


TUWF::get qr{/$RE{iid}/edit}, sub {
    my $e = tuwf->dbRowi('
        SELECT i.id, i.name, i.alias, i.description, i.state, i.sexual, i.defaultspoil, i.searchable, i.applicable, i.order
             , ', sql_user('u', 'addedby_'), '
          FROM traits i
          LEFT JOIN users u ON i.addedby = u.id
         WHERE i.id =', \tuwf->capture('id')
    );
    return tuwf->resNotFound if !$e->{id};

    enrich parents => id => trait => '
        SELECT ip.trait, i.id, i.name, g.name AS group
          FROM traits_parents ip JOIN traits i ON i.id = ip.parent LEFT JOIN traits g ON g.id = i.group WHERE ip.trait IN', $e;

    return tuwf->resDenied if !can_edit i => $e;

    $e->{addedby} = xml_string sub { user_ $e, 'addedby_'; };
    $e->{can_mod} = auth->permTagmod;

    framework_ title => "Edit $e->{name}", type => 'i', dbobj => $e, tab => 'edit', sub {
        elm_ TraitEdit => $FORM_OUT, $e;
    };
};


TUWF::get qr{/(?:$RE{iid}/add|i/new)}, sub {
    my $id = tuwf->capture('id');
    my $i = tuwf->dbRowi('SELECT i.id, i.name, g.name AS "group", i.sexual FROM traits i LEFT JOIN traits g ON g.id = i."group" WHERE i.id =', \$id);
    return tuwf->resDenied if !can_edit i => {};
    return tuwf->resNotFound if $id && !$i->{id};

    my $e = elm_empty($FORM_OUT);
    $e->{can_mod} = auth->permTagmod;
    if($id) {
        $e->{parents} = [$i];
        $e->{sexual} = $i->{sexual};
    }

    framework_ title => 'Submit a new trait', sub {
        div_ class => 'mainbox', sub {
            h1_ 'Requesting new trait';
            div_ class => 'notice', sub {
                h2_ 'Your trait must be approved';
                p_ sub {
                    txt_ 'All traits have to be approved by a moderator, so it can take a while before it will show up in the trait list.';
                    br_;
                    br_;
                    txt_ 'Make sure you\'ve read the '; a_ href => '/d10', 'guidelines'; txt_ ' to increase the chances of getting your trait accepted.';
                }
            }
        } if !auth->permTagmod;
        elm_ TraitEdit => $FORM_OUT, $e;
    };
};


elm_api TraitEdit => $FORM_OUT, $FORM_IN, sub {
    my($data) = @_;
    my $id = delete $data->{id};
    my $e = !$id ? {} : tuwf->dbRowi('SELECT id, addedby, state FROM traits WHERE id =', \$id);
    return tuwf->resNotFound if $id && !$e->{id};
    return elm_Unauth if !can_edit i => $e;


    $data->{addedby} = $id ? $e->{addedby} : auth->uid;
    if(!auth->permTagmod) {
        $data->{state} = 0;
        $data->{applicable} = $data->{searchable} = 1;
    }
    $data->{order} = 0 if $data->{parents}->@*;

    # Make sure parent IDs exists and are not a child trait of the current trait (i.e. don't allow cycles)
    my @parents = map $_->{id}, $data->{parents}->@*;
    validate_dbid sub {
        'SELECT id FROM traits WHERE', sql_and
            $id ? sql 'id NOT IN(WITH RECURSIVE t(id) AS (SELECT', \$id, '::int UNION SELECT trait FROM traits_parents tp JOIN t ON t.id = tp.parent) SELECT id FROM t)' : (),
            sql 'id IN', $_[0]
    }, @parents;

    # It's technically possible for a trait to be in multiple groups, but the DB schema doesn't support that so let's get the group from the first parent (sorted by id).
    $data->{group} = tuwf->dbVali('SELECT coalesce("group",id) FROM traits WHERE id IN', \@parents, 'ORDER BY id LIMIT 1');

    # (Ideally this checks all groups that this trait applies in, but that's more annoying to implement)
    my $re = '[\t\s]*\n[\t\s]*';
    my $dups = tuwf->dbAlli('
        SELECT n.id, n.name
          FROM (SELECT id, name FROM traits UNION ALL SELECT id, s FROM traits, regexp_split_to_table(alias, ', \$re, ') a(s) WHERE s <> \'\') n(id,name)
          JOIN traits t ON n.id = t.id
         WHERE ', sql_and(
             $id ? sql 'n.id <>', \$id : (),
             sql('t."group" IS NOT DISTINCT FROM', \$data->{group}),
             sql 'lower(n.name) IN', [ map lc($_), $data->{name}, grep length($_), split /$re/, $data->{alias} ]
         )
    );
    return elm_DupNames $dups if @$dups;

    $data->{description} = bb_subst_links($data->{description});

    my %set = map +($_,$data->{$_}), qw/name alias description state addedby sexual defaultspoil searchable applicable/;
    $set{'"group"'} = $data->{group};
    $set{'"order"'} = $data->{order};
    $set{added} = sql 'NOW()' if $id && $data->{state} == 2 && $e->{state} != 2;
    tuwf->dbExeci('UPDATE traits SET', \%set, 'WHERE id =', \$id) if $id;
    $id = tuwf->dbVali('INSERT INTO traits', \%set, 'RETURNING id') if !$id;

    tuwf->dbExeci('DELETE FROM traits_parents WHERE trait =', \$id);
    tuwf->dbExeci('INSERT INTO traits_parents (trait,parent) VALUES(', \$id, ',', \$_->{id}, ')') for $data->{parents}->@*;

    auth->audit(undef, 'trait edit', "i$id") if $id; # Since we don't have edit histories for traits yet.
    elm_Redirect "/i$id";
};

1;
