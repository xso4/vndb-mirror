package VNWeb::ULists::JS;

use VNWeb::Prelude;
use VNWeb::ULists::Lib;


# Should be called after any label/vote/private change to the ulist_vns table.
# (Normally I'd do this with triggers, but that seemed like a more complex and less efficient solution in this case)
sub updcache {
    tuwf->dbExeci(SELECT => sql_func update_users_ulist_private => \auth->uid, \$_[0]) if @_ == 1;
    tuwf->dbExeci(SELECT => sql_func update_users_ulist_stats => \auth->uid);
}


sub sql_labelid {
    sql '(SELECT min(x.n)
           FROM generate_series(10,
                  greatest((SELECT max(id)+1 from ulist_labels ul WHERE ul.uid =', \auth->uid, '), 10)
                ) x(n)
          WHERE NOT EXISTS(SELECT 1 FROM ulist_labels ul WHERE ul.uid =', \auth->uid, 'AND ul.id = x.n))';
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
    return tuwf->resDenied if !auth;

    # Insert new labels
    my @new = grep $_->{id} < 0 && !$_->{delete}, @$labels;
    tuwf->dbExeci('INSERT INTO ulist_labels', { id => sql_labelid, uid => auth->uid, label => $_->{label}, private => $_->{private} }) for @new;

    # Update private flag
    my $changed = 0;
    $changed += tuwf->dbExeci(
        'UPDATE ulist_labels SET private =', \$_->{private},
         'WHERE uid =', \auth->uid, 'AND id =', \$_->{id}, 'AND private <>', \$_->{private}
    ) for grep $_->{id} > 0 && !$_->{delete}, @$labels;

    # Update label
    tuwf->dbExeci(
        'UPDATE ulist_labels SET label =', \$_->{label},
         'WHERE uid =', \auth->uid, 'AND id =', \$_->{id}, 'AND label <>', \$_->{label}
    ) for grep $_->{id} >= 10 && !$_->{delete}, @$labels;

    # Delete labels
    my @delete = grep $_->{id} >= 10 && $_->{delete}, @$labels;
    my @delete_lblonly = map $_->{id}, grep $_->{delete} == 1, @delete;
    my @delete_empty   = map $_->{id}, grep $_->{delete} == 2, @delete;
    my @delete_all     = map $_->{id}, grep $_->{delete} == 3, @delete;

    # delete vns with: (a label in option 3) OR ((a label in option 2) AND (no labels other than in option 1 or 2))
    my @where = (
        @delete_all ? sql('labels &&', sql_array(@delete_all), '::smallint[]') : (),
        @delete_empty ? sql(
                'labels &&', sql_array(@delete_empty), '::smallint[]
             AND labels <@', sql_array(@delete_lblonly, @delete_empty), '::smallint[]'
        ) : ()
    );
    tuwf->dbExeci('DELETE FROM ulist_vns uv WHERE uid =', \auth->uid, 'AND (', sql_or(@where), ')') if @where;

    $changed += tuwf->dbExeci(
        'UPDATE ulist_vns
            SET labels = array_remove(labels,', \$_->{id}, ')
          WHERE uid =', \auth->uid, 'AND labels && ARRAY[', \$_->{id}, '::smallint]'
    ) for @delete;

    tuwf->dbExeci('DELETE FROM ulist_labels WHERE uid =', \auth->uid, 'AND id IN', [ map $_->{id}, @delete ]) if @delete;

    updcache $changed ? undef : ();
    +{}
};



js_api UListVoteEdit => {
    vid  => { vndbid => 'v' },
    vote => { vnvote => 1 },
}, sub($data) {
    return tuwf->resDenied if !auth;
    tuwf->dbExeci(
        'INSERT INTO ulist_vns', { %$data, uid => auth->uid, vote_date => sql $data->{vote} ? 'NOW()' : 'NULL' },
            'ON CONFLICT (uid, vid) DO UPDATE
            SET', { %$data,
                lastmod   => sql('NOW()'),
                vote_date => sql $data->{vote} ? 'CASE WHEN ulist_vns.vote IS NULL THEN NOW() ELSE ulist_vns.vote_date END' : 'NULL'
            }
    );
    updcache $data->{vid};
    +{}
};



js_api UListDateEdit => {
    vid   => { vndbid => 'v' },
    date  => { fuzzyrdate => 1 },
    start => { anybool => 1 }, # Field selection, started/finished
}, sub($data) {
    return tuwf->resDenied if !auth;
    my %set = (
        $data->{start} ? 'started' : 'finished',
        !$data->{date} ? undef : $data->{date} == 1 ? 'today' : $data->{date} =~ s/(....)(..)(..)/$1-$2-$3/r =~ s/-99/-01/r
    );
    tuwf->dbExeci(
        'INSERT INTO ulist_vns', { %set, vid => $data->{vid}, uid => auth->uid },
            'ON CONFLICT (uid, vid) DO UPDATE
            SET', { %set, lastmod => sql('NOW()') }
    );
    # Doesn't need `updcache()`
    +{}
};



js_api UListVNNotes => {
    vid   => { vndbid => 'v' },
    notes => { default => '', maxlength => 2000 },
}, sub($data) {
    return tuwf->resDenied if !auth;
    $data->{uid} = auth->uid;
    tuwf->dbExeci(
        'INSERT INTO ulist_vns', \%$data, 'ON CONFLICT (uid, vid) DO UPDATE SET', { %$data, lastmod => sql('NOW()') }
    );
    # Doesn't need `updcache()`
    +{}
};



js_api UListDel => { vid => { vndbid => 'v' } }, sub {
    my $vid = $_[0]{vid};
    return tuwf->resDenied if !auth;
    tuwf->dbExeci('DELETE FROM ulist_vns WHERE uid =', \auth->uid, 'AND vid =', \$vid);
    updcache;
    +{}
};



js_api UListLabelEdit => {
    vid => { vndbid => 'v' },
    labels => { elems => { uint => 1 } }
}, sub($data) {
    return tuwf->resDenied if !auth;
    # BUG: This should probably check whether the label exists, but APIv2 has the same bug. *shrug*
    my $labels = '{'.join(',', sort { $a <=> $b } grep $_ != 7, $data->{labels}->@*).'}';
    tuwf->dbExeci(
        'INSERT INTO ulist_vns', {
            uid => auth->uid,
            vid => $data->{vid},
            labels => $labels,
        }, 'ON CONFLICT (uid, vid) DO UPDATE
                SET lastmod = NOW()
                  , labels = CASE WHEN ulist_vns.vote IS NULL THEN', \$labels, 'ELSE array_set(', \$labels, ', 7) END'
    );
    updcache $data->{vid};
    +{}
};



js_api UListLabelAdd => {
    vid   => { vndbid => 'v' },
    label => { sl => 1, maxlength => 50 },
}, sub($data) {
    return tuwf->resDenied if !auth;

    my $row = tuwf->dbRowi('
        WITH l(id, private) AS (
          SELECT id, private FROM ulist_labels WHERE uid =', \auth->uid, 'AND label =', \$data->{label}, '
        ), ins(id, private) AS (
          INSERT INTO ulist_labels (id, uid, label, private)
          SELECT ', sql_join(',',
                   sql_labelid, \auth->uid, \$data->{label},
                   # Let's copy the private flag from the Voted label, seems like a sane default
                   sql('(SELECT private FROM ulist_labels WHERE', {uid => auth->uid, id => 7}, ')'),
                 ), '
           WHERE NOT EXISTS(SELECT 1 FROM l)
          RETURNING id, private
        ) SELECT * FROM l UNION SELECT * FROM ins'
    );

    tuwf->dbExeci(
        'INSERT INTO ulist_vns', {uid => auth->uid, vid => $data->{vid}, labels => "{$row->{id}}"},
        'ON CONFLICT (uid, vid) DO UPDATE SET labels = array_set(ulist_vns.labels,', \$row->{id}, ')'
    );
    updcache $data->{vid};
    +{ id => $row->{id}*1, priv => $row->{priv}?\1:\0 }
};



js_api UListRStatus => {
    rid => { vndbid => 'r' },
    status => { default => undef, uint => 1, enum => \%RLIST_STATUS }, # undef meaning delete
}, sub($data) {
    return tuwf->resDenied if !auth;
    $data->{uid} = auth->uid;
    if(!defined $data->{status}) {
        tuwf->dbExeci('DELETE FROM rlists WHERE uid =', \$data->{uid}, 'AND rid =', \$data->{rid})
    } else {
        tuwf->dbExeci('INSERT INTO rlists', $data, 'ON CONFLICT (uid, rid) DO UPDATE SET status =', \$data->{status})
    }
    # Doesn't need `updcache()`
    +{}
};



js_api UListWidget => { vid => { vndbid => 'v' } }, sub($data) {
    return tuwf->resDenied if !auth;
    my $v = tuwf->dbRowi('SELECT id, title, c_released FROM', vnt, 'v WHERE id =', \$data->{vid});
    return tuwf->resNotFound if !defined $v->{title};
    +{ results => ulists_widget_full_data $v };
};

1;
