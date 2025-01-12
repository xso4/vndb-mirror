package VNWeb::TT::TraitEdit;

use VNWeb::Prelude;

my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    id           => { default => undef, vndbid => 'i' },
    name         => { maxlength => 250, sl => 1 },
    alias        => { maxlength => 1024, default => '' },
    sexual       => { anybool => 1 },
    description  => { maxlength => 10240 },
    searchable   => { anybool => 1, default => 1 },
    applicable   => { anybool => 1, default => 1 },
    defaultspoil => { uint => 1, range => [0,2] },
    parents      => { aoh => {
        parent      => { vndbid => 'i' },
        main        => { anybool => 1 },
        name        => { _when => 'out' },
        group       => { _when => 'out', default => undef },
    } },
    gorder       => { uint => 1 },
    hidden       => { anybool => 1 },
    locked       => { anybool => 1 },

    authmod      => { _when => 'out', anybool => 1 },
    editsum      => { editsum => 1 },
};


TUWF::get qr{/$RE{irev}/edit}, sub {
    my $e = db_entry tuwf->captures('id','rev');
    return tuwf->resNotFound if !$e->{id};
    return tuwf->resDenied if !can_edit i => $e;

    $e->{authmod} = auth->permTagmod;
    $e->{editsum} = $e->{chrev} == $e->{maxrev} ? '' : "Reverted to revision $e->{id}.$e->{chrev}";

    framework_ title => "Edit $e->{name}", dbobj => $e, tab => 'edit', sub {
        div_ widget(TraitEdit => $FORM_OUT, $e), '';
    };
};


TUWF::get qr{/(?:$RE{iid}/add|i/new)}, sub {
    my $id = tuwf->capture('id');
    my $i = tuwf->dbRowi('SELECT i.id AS parent, i.name, g.name AS "group", i.sexual FROM traits i LEFT JOIN traits g ON g.id = i.gid WHERE i.id =', \$id);
    return tuwf->resDenied if !can_edit i => {};
    return tuwf->resNotFound if $id && !$i->{parent};

    my $e = elm_empty($FORM_OUT);
    $e->{authmod} = auth->permTagmod;
    if($id) {
        $i->{main} = 1;
        $e->{parents} = [$i];
        $e->{sexual} = $i->{sexual};
    }

    framework_ title => 'Submit a new trait', sub {
        article_ sub {
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
        div_ widget(TraitEdit => $FORM_OUT, $e), '';
    };
};


js_api TraitEdit => $FORM_IN, sub {
    my($data) = @_;
    my $new = !$data->{id};
    my $e = $new ? {} : db_entry $data->{id} or return tuwf->resNotFound;
    return tuwf->resNotFound if !$new && !$e->{id};
    return tuwf->resDenied if !can_edit i => $e;

    if(!auth->permTagmod) {
        $data->{hidden} = $e->{hidden}//1;
        $data->{locked} = $e->{locked}//0;
    }
    $data->{gorder} = 0 if $data->{parents}->@*;

    # Make sure parent IDs exists and are not a child trait of the current trait (i.e. don't allow cycles)
    my @parents = map $_->{parent}, $data->{parents}->@*;
    validate_dbid sub {
        'SELECT id FROM traits WHERE', sql_and
            $new ? () : sql('id NOT IN(WITH RECURSIVE t(id) AS (SELECT', \$e->{id}, '::vndbid UNION SELECT tp.id FROM traits_parents tp JOIN t ON t.id = tp.parent) SELECT id FROM t)'),
            sql 'id IN', $_[0]
    }, @parents;
    die "No or multiple primary parents" if $data->{parents}->@* && 1 != grep $_->{main}, $data->{parents}->@*;

    my $group = tuwf->dbVali('SELECT coalesce(gid,id) FROM traits WHERE id =', \[grep $_->{main}, $data->{parents}->@*]->[0]{parent});

    $data->{description} = bb_subst_links($data->{description});

    # (Ideally this checks all groups that this trait applies in, but that's more annoying to implement)
    my $re = '[\t\s]*\n[\t\s]*';
    my $dups = tuwf->dbAlli('
        SELECT n.id, n.name
          FROM (SELECT id, name FROM traits UNION ALL SELECT id, s FROM traits, regexp_split_to_table(alias, ', \$re, ') a(s) WHERE s <> \'\') n(id,name)
          JOIN traits t ON n.id = t.id
         WHERE ', sql_and(
             $new ? () : sql('n.id <>', \$e->{id}),
             sql('t.gid IS NOT DISTINCT FROM', \$group),
             sql 'lower(n.name) IN', [ map lc($_), $data->{name}, grep length($_), split /$re/, $data->{alias} ]
         )
    );
    return +{ dups => $dups } if @$dups;

    my $ch = db_edit i => $e->{id}, $data;
    return 'No changes.' if !$ch->{nitemid};
    tuwf->dbExeci('UPDATE traits SET gid = null WHERE id =', \$ch->{nitemid}) if !$group;
    tuwf->dbExeci('
        WITH RECURSIVE childs (id) AS (
            SELECT ', \$ch->{nitemid}, '::vndbid UNION ALL SELECT tp.id FROM childs JOIN traits_parents tp ON tp.parent = childs.id AND tp.main
        ) UPDATE traits SET gid =', \$group, 'WHERE id IN(SELECT id FROM childs) AND gid IS DISTINCT FROM', \$group
    ) if $group;
    return +{ _redir => "/$ch->{nitemid}.$ch->{nrev}" };
};

1;
