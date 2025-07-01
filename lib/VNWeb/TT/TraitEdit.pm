package VNWeb::TT::TraitEdit;

use VNWeb::Prelude;

my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    id           => { default => undef, vndbid => 'i' },
    name         => { maxlength => 250, sl => 1 },
    alias        => { maxlength => 1024, default => '' },
    sexual       => { anybool => 1 },
    description  => { maxlength => 10240 },
    searchable   => { anybool => 1 },
    applicable   => { anybool => 1 },
    defaultspoil => { uint => 1, range => [0,2] },
    parents      => { sort_keys => 'parent', aoh => {
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
    maxrev       => { default => undef, uint => 1 },
};


FU::get qr{/$RE{irev}/edit}, sub($id, $rev=0) {
    my $e = db_entry $id, $rev or fu->notfound;
    fu->denied if !can_edit i => $e;

    $e->{authmod} = auth->permTagmod;
    $e->{editsum} = $e->{chrev} == $e->{maxrev} ? '' : "Reverted to revision $e->{id}.$e->{chrev}";

    framework_ title => "Edit $e->{name}", dbobj => $e, tab => 'edit', sub {
        div_ widget(TraitEdit => $FORM_OUT, $e), '';
    };
};


FU::get qr{/(?:$RE{iid}/add|i/new)}, sub($id=undef) {
    my $i = $id && fu->SQL('SELECT i.id AS parent, i.name, g.name AS "group", i.sexual FROM traits i LEFT JOIN traits g ON g.id = i.gid WHERE i.id =', $id)->rowh;
    fu->denied if !can_edit i => {};
    fu->notfound if $id && !$i->{parent};

    my $e = $FORM_OUT->empty;
    $e->{authmod} = auth->permTagmod;
    $e->{applicable} = $e->{searchable} = 1;
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


js_api TraitEdit => $FORM_IN, sub($data) {
    my $new = !$data->{id};
    my $e = $new ? {} : db_entry $data->{id} or fu->notfound;
    fu->notfound if !$new && !$e->{id};
    fu->denied if !can_edit i => $e;

    validate_maxrev $data, $e;
    if(!auth->permTagmod) {
        $data->{hidden} = $e->{hidden}//1;
        $data->{locked} = $e->{locked}//0;
    }
    $data->{gorder} = 0 if $data->{parents}->@*;

    # Make sure parent IDs exists and are not a child trait of the current trait (i.e. don't allow cycles)
    my @parents = map $_->{parent}, $data->{parents}->@*;
    validate_dbid sub { SQL
        'SELECT id FROM traits WHERE id', IN $_,
            $new ? () : SQL('AND id NOT IN(WITH RECURSIVE t(id) AS (SELECT', $e->{id}, '::vndbid UNION SELECT tp.id FROM traits_parents tp JOIN t ON t.id = tp.parent) SELECT id FROM t)'),
    }, @parents;
    return 'There should be exactly one primary parent' if $data->{parents}->@* && 1 != grep $_->{main}, $data->{parents}->@*;

    my $group = fu->SQL('SELECT coalesce(gid,id) FROM traits WHERE id =', [grep $_->{main}, $data->{parents}->@*]->[0]{parent})->val;

    $data->{description} = bb_subst_links($data->{description});

    # (Ideally this checks all groups that this trait applies in, but that's more annoying to implement)
    my $re = '[\t\s]*\n[\t\s]*';
    my $dups = fu->SQL('
        SELECT n.id, n.name
          FROM (SELECT id, name FROM traits UNION ALL SELECT id, s FROM traits, regexp_split_to_table(alias, ', $re, ') a(s) WHERE s <> \'\') n(id,name)
          JOIN traits t ON n.id = t.id
         WHERE ', AND(
             $new ? () : SQL('n.id <>', $e->{id}),
             SQL('t.gid IS NOT DISTINCT FROM', $group),
             SQL 'lower(n.name)', IN [ map lc($_), $data->{name}, grep length($_), split /$re/, $data->{alias} ]
         )
    )->allh;
    return +{ dups => $dups } if @$dups;

    my $ch = db_edit i => $e->{id}, $data;
    return 'No changes.' if !$ch->{nitemid};
    fu->SQL('UPDATE traits SET gid = null WHERE id =', $ch->{nitemid})->exec if !$group;
    fu->SQL('
        WITH RECURSIVE childs (id) AS (
            SELECT ', $ch->{nitemid}, '::vndbid UNION ALL SELECT tp.id FROM childs JOIN traits_parents tp ON tp.parent = childs.id AND tp.main
        ) UPDATE traits SET gid =', $group, 'WHERE id IN(SELECT id FROM childs) AND gid IS DISTINCT FROM', $group
    )->exec if $group;
    return +{ _redir => "/$ch->{nitemid}.$ch->{nrev}" };
};

1;
