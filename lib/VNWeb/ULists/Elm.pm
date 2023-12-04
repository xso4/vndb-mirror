package VNWeb::ULists::Elm;

use VNWeb::Prelude;
use VNWeb::ULists::Lib;


# Should be called after any label/vote/private change to the ulist_vns table.
# (Normally I'd do this with triggers, but that seemed like a more complex and less efficient solution in this case)
sub updcache {
    my($uid,$vid) = @_;
    tuwf->dbExeci(SELECT => sql_func update_users_ulist_private => \$uid, \$vid) if @_ == 2;
    tuwf->dbExeci(SELECT => sql_func update_users_ulist_stats => \$uid);
}


sub sql_labelid {
    my($uid) = @_;
    sql '(SELECT min(x.n)
           FROM generate_series(10,
                  greatest((SELECT max(id)+1 from ulist_labels ul WHERE ul.uid =', \$uid, '), 10)
                ) x(n)
          WHERE NOT EXISTS(SELECT 1 FROM ulist_labels ul WHERE ul.uid =', \$uid, 'AND ul.id = x.n))';
}


our $LABELS = form_compile any => {
    uid => { vndbid => 'u' },
    labels => { maxlength => 1500, aoh => {
        id      => { int => 1 },
        label   => { sl => 1, maxlength => 50 },
        private => { anybool => 1 },
        count   => { uint => 1 },
        delete  => { default => undef, uint => 1, range => [1, 3] }, # 1=keep vns, 2=delete when no other label, 3=delete all
    } }
};

elm_api UListManageLabels => undef, $LABELS, sub {
    my($uid, $labels) = ($_[0]{uid}, $_[0]{labels});
    return elm_Unauth if !ulists_own $uid;

    # Insert new labels
    my @new = grep $_->{id} < 0 && !$_->{delete}, @$labels;
    tuwf->dbExeci('INSERT INTO ulist_labels', { id => sql_labelid($uid), uid => $uid, label => $_->{label}, private => $_->{private} }) for @new;

    # Update private flag
    my $changed = 0;
    $changed += tuwf->dbExeci(
        'UPDATE ulist_labels SET private =', \$_->{private},
         'WHERE uid =', \$uid, 'AND id =', \$_->{id}, 'AND private <>', \$_->{private}
    ) for grep $_->{id} > 0 && !$_->{delete}, @$labels;

    # Update label
    tuwf->dbExeci(
        'UPDATE ulist_labels SET label =', \$_->{label},
         'WHERE uid =', \$uid, 'AND id =', \$_->{id}, 'AND label <>', \$_->{label}
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
    tuwf->dbExeci('DELETE FROM ulist_vns uv WHERE uid =', \$uid, 'AND (', sql_or(@where), ')') if @where;

    $changed += tuwf->dbExeci(
        'UPDATE ulist_vns
            SET labels = array_remove(labels,', \$_->{id}, ')
          WHERE uid =', \$uid, 'AND labels && ARRAY[', \$_->{id}, '::smallint]'
    ) for @delete;

    tuwf->dbExeci('DELETE FROM ulist_labels WHERE uid =', \$uid, 'AND id IN', [ map $_->{id}, @delete ]) if @delete;

    updcache $uid, $changed ? undef : ();
    elm_Success
};


# Create a new label and add it to a VN
elm_api UListLabelAdd => undef, {
    uid   => { vndbid => 'u' },
    vid   => { vndbid => 'v' },
    label => { sl => 1, maxlength => 50 },
}, sub {
    my($data) = @_;
    return elm_Unauth if !ulists_own $data->{uid};

    my $id = tuwf->dbVali('
        WITH x(id) AS (SELECT id FROM ulist_labels WHERE', { uid => $data->{uid}, label => $data->{label} }, '),
             y(id) AS (INSERT INTO ulist_labels (id, uid, label, private) SELECT', sql_join(',',
                sql_labelid($data->{uid}), \$data->{uid}, \$data->{label},
                # Let's copy the private flag from the Voted label, seems like a sane default
                sql('(SELECT private FROM ulist_labels WHERE', {uid => $data->{uid}, id => 7}, ')')
            ), 'WHERE NOT EXISTS(SELECT 1 FROM x) RETURNING id)
        SELECT id FROM x UNION SELECT id FROM y'
    );
    die "Attempt to set vote label" if $id == 7;

    tuwf->dbExeci(
        'INSERT INTO ulist_vns', {uid => $data->{uid}, vid => $data->{vid}, labels => "{$id}"},
        'ON CONFLICT (uid, vid) DO UPDATE SET labels = array_set(ulist_vns.labels,', \$id, ')'
    );
    updcache $data->{uid}, $data->{vid};
    elm_LabelId $id
};



our $VNVOTE = form_compile any => {
    uid  => { vndbid => 'u' },
    vid  => { vndbid => 'v' },
    vote => { vnvote => 1 },
};

elm_api UListVoteEdit => undef, $VNVOTE, sub {
    my($data) = @_;
    return elm_Unauth if !ulists_own $data->{uid};
    tuwf->dbExeci(
        'INSERT INTO ulist_vns', { %$data, vote_date => sql $data->{vote} ? 'NOW()' : 'NULL' },
            'ON CONFLICT (uid, vid) DO UPDATE
            SET', { %$data,
                lastmod   => sql('NOW()'),
                vote_date => sql $data->{vote} ? 'CASE WHEN ulist_vns.vote IS NULL THEN NOW() ELSE ulist_vns.vote_date END' : 'NULL'
            }
    );
    updcache $data->{uid}, $data->{vid};
    elm_Success
};




my $VNLABELS = {
    uid      => { vndbid => 'u' },
    vid      => { vndbid => 'v' },
    label    => { _when => 'in', id => 1 },
    applied  => { _when => 'in', anybool => 1 },
    labels   => { _when => 'out', aoh => { id => { int => 1 }, label => {}, private => { anybool => 1 } } },
    selected => { _when => 'out', type => 'array', values => { id => 1 } },
};

our $VNLABELS_OUT = form_compile out => $VNLABELS;
my  $VNLABELS_IN  = form_compile in  => $VNLABELS;

elm_api UListLabelEdit => $VNLABELS_OUT, $VNLABELS_IN, sub {
    my($data) = @_;
    return elm_Unauth if !ulists_own $data->{uid};
    die "Attempt to set vote label" if $data->{label} == 7;
    die "Attempt to set invalid label" if $data->{applied}
        && !tuwf->dbVali('SELECT 1 FROM ulist_labels WHERE uid =', \$data->{uid}, 'AND id =', \$data->{label});

    tuwf->dbExeci(
        'INSERT INTO ulist_vns', {
            uid => $data->{uid},
            vid => $data->{vid},
            labels => $data->{applied}?"{$data->{label}}":'{}'
        }, 'ON CONFLICT (uid, vid) DO UPDATE SET lastmod = NOW(),
              labels =', sql_func $data->{applied} ? 'array_set' : 'array_remove', 'ulist_vns.labels', \$data->{label}
    );
    updcache $data->{uid}, $data->{vid};
    elm_Success
};




our $VNDATE = form_compile any => {
    uid   => { vndbid => 'u' },
    vid   => { vndbid => 'v' },
    date  => { default => '', caldate => 1 },
    start => { anybool => 1 }, # Field selection, started/finished
};

elm_api UListDateEdit => undef, $VNDATE, sub {
    my($data) = @_;
    return elm_Unauth if !ulists_own $data->{uid};
    tuwf->dbExeci(
        'UPDATE ulist_vns SET lastmod = NOW(), ', $data->{start} ? 'started' : 'finished', '=', \($data->{date}||undef),
         'WHERE uid =', \$data->{uid}, 'AND vid =', \$data->{vid}
    );
    # Doesn't need `updcache()`
    elm_Success
};




our $VNOPT = form_compile any => {
    own   => { anybool => 1 },
    uid   => { vndbid => 'u' },
    vid   => { vndbid => 'v' },
    notes => {},
    rels  => $VNWeb::Elm::apis{Releases}[0],
    relstatus => { type => 'array', values => { uint => 1 } }, # List of release statuses, same order as rels
};


# UListVNNotes module is abused for the UList.Opts flag definition
elm_api UListVNNotes => $VNOPT, {
    uid   => { vndbid => 'u' },
    vid   => { vndbid => 'v' },
    notes => { default => '', maxlength => 2000 },
}, sub {
    my($data) = @_;
    return elm_Unauth if !ulists_own $data->{uid};
    tuwf->dbExeci(
        'INSERT INTO ulist_vns', \%$data, 'ON CONFLICT (uid, vid) DO UPDATE SET', { %$data, lastmod => sql('NOW()') }
    );
    # Doesn't need `updcache()`
    elm_Success
};




elm_api UListDel => undef, {
    uid => { vndbid => 'u' },
    vid => { vndbid => 'v' },
}, sub {
    my($data) = @_;
    return elm_Unauth if !ulists_own $data->{uid};
    tuwf->dbExeci('DELETE FROM ulist_vns WHERE uid =', \$data->{uid}, 'AND vid =', \$data->{vid});
    updcache $data->{uid};
    elm_Success
};




# Adds the release when not in the list.
# $RLIST_STATUS is also referenced from VNWeb::Releases::Page.
our $RLIST_STATUS = form_compile any => {
    uid => { vndbid => 'u' },
    rid => { vndbid => 'r' },
    status => { default => undef, uint => 1, enum => \%RLIST_STATUS }, # undef meaning delete
    empty => { default => '' }, # An 'out' field
};
elm_api UListRStatus => undef, $RLIST_STATUS, sub {
    my($data) = @_;
    delete $data->{empty};
    return elm_Unauth if !ulists_own $data->{uid};
    if(!defined $data->{status}) {
        tuwf->dbExeci('DELETE FROM rlists WHERE uid =', \$data->{uid}, 'AND rid =', \$data->{rid})
    } else {
        tuwf->dbExeci('INSERT INTO rlists', $data, 'ON CONFLICT (uid, rid) DO UPDATE SET status =', \$data->{status})
    }
    # Doesn't need `updcache()`
    elm_Success
};



our $WIDGET = form_compile out => $VNWeb::Elm::apis{UListWidget}[0]{keys};

elm_api UListWidget => $WIDGET, { uid => { vndbid => 'u' }, vid => { vndbid => 'v' } }, sub {
    my($data) = @_;
    return elm_Unauth if !ulists_own $data->{uid};
    my $v = tuwf->dbRowi('SELECT id, title, c_released FROM', vnt, 'v WHERE id =', \$data->{vid});
    return elm_Invalid if !defined $v->{title};
    elm_UListWidget ulists_widget_full_data $v, $data->{uid};
};




our %SAVED_OPTS = (
    l   => { onerror => [], type => 'array', scalar => 1, values => { int => 1, range => [-1,1600] } },
    mul => { anybool => 1 },
    s   => { onerror => '' }, # TableOpts query string
    f   => { onerror => '' }, # AdvSearch
);

my $SAVED_OPTS = {
    uid   => { vndbid => 'u' },
    opts  => { type => 'hash', keys => \%SAVED_OPTS },
    field => { _when => 'in', enum => [qw/ vnlist votes wish /] },
};

my  $SAVED_OPTS_IN  = form_compile in  => $SAVED_OPTS;
our $SAVED_OPTS_OUT = form_compile out => $SAVED_OPTS;

elm_api UListSaveDefault => $SAVED_OPTS_OUT, $SAVED_OPTS_IN, sub {
    my($data) = @_;
    return elm_Unauth if !ulists_own $data->{uid};
    tuwf->dbExeci('UPDATE users_prefs SET ulist_'.$data->{field}, '=', \JSON::XS->new->encode($data->{opts}), 'WHERE id =', \$data->{uid});
    elm_Success
};

1;
