package VNWeb::ULists::JS;

use VNWeb::Prelude;
use VNWeb::ULists::Lib;


# Should be called after any label/vote/private change to the ulist_vns table.
# (Normally I'd do this with triggers, but that seemed like a more complex and less efficient solution in this case)
sub updcache {
    fu->sql('SELECT update_users_ulist_private($1, $2)', auth->uid, $_[0])->exec if @_ == 1;
    fu->sql('SELECT update_users_ulist_stats($1)', auth->uid)->exec;
}


# Add a new label if none exist with that name yet. Returns (id,private)
# Does not update the private flag if the label already exists.
sub addlabel($label, $private=undef) {
    # Let's copy the private flag from the Voted label, seems like a sane default
    $private //= SQL('(SELECT private FROM ulist_labels', WHERE({uid => auth->uid, id => 7}), ')');
    fu->SQL('
        WITH l(id, private) AS (
          SELECT id, private FROM ulist_labels WHERE uid =', auth->uid, 'AND label =', $label, '
        ), ins(id, private) AS (
          INSERT INTO ulist_labels (id, uid, label, private)
          SELECT (SELECT min(x.n) FROM generate_series(10,
                      greatest((SELECT max(id)+1 from ulist_labels ul WHERE ul.uid =', auth->uid, '), 10)
                 ) x(n) WHERE NOT EXISTS(SELECT 1 FROM ulist_labels ul WHERE ul.uid =', auth->uid, 'AND ul.id = x.n))
               , ', auth->uid, ',', $label, ',', $private, '
           WHERE NOT EXISTS(SELECT 1 FROM l)
          RETURNING id, private
        ) SELECT * FROM l UNION SELECT * FROM ins'
    )->rowl;
}


js_api UListManageLabels => {
    labels => { maxlength => 1500, aoh => {
        id      => { int => 1 },
        label   => { sl => 1, maxlength => 50 },
        private => { anybool => 1 },
        delete  => { default => undef, uint => 1, range => [1, 3] }, # 1=keep vns, 2=delete when no other label, 3=delete all
    }}
}, sub {
    my $labels = $_[0]{labels};
    fu->denied if !auth;
    my $changed = 0;

    # Delete labels
    my @delete = grep $_->{id} >= 10 && $_->{delete}, @$labels;
    my @delete_lblonly = map $_->{id}, grep $_->{delete} == 1, @delete;
    my @delete_empty   = map $_->{id}, grep $_->{delete} == 2, @delete;
    my @delete_all     = map $_->{id}, grep $_->{delete} == 3, @delete;

    # delete vns with: (a label in option 3) OR ((a label in option 2) AND (no labels other than in option 1 or 2))
    my @where = (
        @delete_all ? SQL('labels &&', \@delete_all) : (),
        @delete_empty ? SQL('labels &&', \@delete_empty, 'AND labels <@', [@delete_lblonly, @delete_empty]) : ()
    );
    fu->SQL('DELETE FROM ulist_vns uv WHERE uid =', auth->uid, 'AND (', OR(@where), ')')->exec if @where;

    $changed += fu->SQL(
        'UPDATE ulist_vns
            SET labels = array_remove(labels,', $_->{id}, ')
          WHERE uid =', auth->uid, 'AND ', $_->{id}, '= ANY(labels)'
    )->exec for @delete;

    fu->SQL('DELETE FROM ulist_labels WHERE uid =', auth->uid, 'AND id', IN [ map $_->{id}, @delete ])->exec if @delete;

    # Update label
    fu->SQL(
        'UPDATE ulist_labels SET label =', $_->{label},
         'WHERE uid =', auth->uid, 'AND id =', $_->{id}, 'AND label <>', $_->{label}
    )->exec for grep $_->{id} >= 10 && !$_->{delete}, @$labels;

    # Insert new labels
    ($_->{id}) = addlabel($_->{label}, $_->{private}) for grep $_->{id} < 0 && !$_->{delete}, @$labels;

    # Update private flag
    $changed += fu->SQL(
        'UPDATE ulist_labels SET private =', $_->{private},
         'WHERE uid =', auth->uid, 'AND id =', $_->{id}, 'AND private <>', $_->{private}
    )->exec for grep !$_->{delete}, @$labels;

    updcache $changed ? undef : ();
    +{}
};



js_api UListVoteEdit => {
    vid  => { vndbid => 'v' },
    vote => { vnvote => 1 },
}, sub($data) {
    fu->denied if !auth;
    fu->SQL(
        'INSERT INTO ulist_vns', VALUES({ %$data, uid => auth->uid, vote_date => RAW($data->{vote} ? 'NOW()' : 'NULL') }),
            'ON CONFLICT (uid, vid) DO UPDATE', SET { %$data,
                lastmod   => time,
                vote_date => RAW($data->{vote} ? 'COALESCE(ulist_vns.vote_date, NOW())' : 'NULL')
            }
    )->exec;
    updcache $data->{vid};
    +{}
};



js_api UListDateEdit => {
    vid   => { vndbid => 'v' },
    date  => { fuzzyrdate => 1 },
    start => { anybool => 1 }, # Field selection, started/finished
}, sub($data) {
    fu->denied if !auth;
    my %set = (
        $data->{start} ? 'started' : 'finished',
        !$data->{date} ? undef : $data->{date} == 1 ? 'today' : $data->{date} =~ s/(....)(..)(..)/$1-$2-$3/r =~ s/-99/-01/r
    );
    fu->SQL(
        'INSERT INTO ulist_vns', VALUES({ %set, vid => $data->{vid}, uid => auth->uid }),
            'ON CONFLICT (uid, vid) DO UPDATE', SET { %set, lastmod => RAW('NOW()') }
    )->exec;
    # Doesn't need `updcache()`
    +{}
};



js_api UListVNNotes => {
    vid   => { vndbid => 'v' },
    notes => { default => '', maxlength => 2000 },
}, sub($data) {
    fu->denied if !auth;
    $data->{uid} = auth->uid;
    fu->SQL(
        'INSERT INTO ulist_vns', VALUES(\%$data), 'ON CONFLICT (uid, vid) DO UPDATE', SET { %$data, lastmod => RAW('NOW()') }
    )->exec;
    # Doesn't need `updcache()`
    +{}
};



js_api UListDel => { vid => { vndbid => 'v' } }, sub {
    my $vid = $_[0]{vid};
    fu->denied if !auth;
    fu->SQL('DELETE FROM ulist_vns WHERE uid =', auth->uid, 'AND vid =', $vid)->exec;
    updcache;
    +{}
};



js_api UListLabelEdit => {
    vid => { vndbid => 'v' },
    labels => { elems => { uint => 1 } }
}, sub($data) {
    fu->denied if !auth;
    fu->SQL('
        WITH l(l) AS (
          SELECT array_agg(id ORDER BY id) FROM ulist_labels
           WHERE uid =', auth->uid, 'AND id <> 7 AND id', IN($data->{labels}), '
        ) INSERT INTO ulist_vns (uid, vid, labels)
          VALUES (', auth->uid, ',', $data->{vid}, ', (SELECT l FROM l))
          ON CONFLICT (uid, vid) DO UPDATE
            SET lastmod = NOW()
              , labels = CASE WHEN ulist_vns.vote IS NULL THEN (SELECT l FROM l) ELSE array_set((SELECT l FROM l), 7) END'
    )->exec;
    updcache $data->{vid};
    +{}
};



js_api UListLabelAdd => {
    vid   => { vndbid => 'v' },
    label => { sl => 1, maxlength => 50 },
}, sub($data) {
    fu->denied if !auth;

    my($id, $private) = addlabel($data->{label});
    fu->SQL(
        'INSERT INTO ulist_vns', VALUES({uid => auth->uid, vid => $data->{vid}, labels => [$id]}),
        'ON CONFLICT (uid, vid) DO UPDATE SET labels = array_set(ulist_vns.labels,', $id, ')'
    )->exec;
    updcache $data->{vid};
    +{ id => $id, priv => $private }
};



js_api UListRStatus => {
    rid => { vndbid => 'r' },
    status => { default => undef, uint => 1, enum => \%RLIST_STATUS }, # undef meaning delete
}, sub($data) {
    fu->denied if !auth;
    $data->{uid} = auth->uid;
    if(!defined $data->{status}) {
        fu->SQL('DELETE FROM rlists WHERE uid =', $data->{uid}, 'AND rid =', $data->{rid})->exec
    } else {
        fu->SQL('INSERT INTO rlists', VALUES($data), 'ON CONFLICT (uid, rid) DO UPDATE SET status =', $data->{status})->exec
    }
    # Doesn't need `updcache()`
    +{}
};



js_api UListWidget => { vid => { vndbid => 'v' } }, sub($data) {
    fu->denied if !auth;
    my $v = fu->SQL('SELECT id, title, c_released FROM', VNT, 'v WHERE id =', $data->{vid})->rowh or fu->notfound;
    +{ results => ulists_widget_full_data $v };
};

1;
