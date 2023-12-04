package VNWeb::VN::Tagmod;

use VNWeb::Prelude;


my $FORM = {
    id    => { vndbid => 'v' },
    title => { _when => 'out' },
    tags  => { sort_keys => 'id', aoh => {
        id        => { vndbid => 'g' },
        vote      => { int => 1, enum => [ -3..3 ] },
        spoil     => { default => undef, uint => 1, enum => [ 0..2 ] },
        lie       => { undefbool => 1 },
        overrule  => { anybool => 1 },
        notes     => { default => '', sl => 1, maxlength => 1000 },
        cat       => { _when => 'out' },
        name      => { _when => 'out' },
        rating    => { _when => 'out', num => 1 },
        count     => { _when => 'out', uint => 1 },
        spoiler   => { _when => 'out', num => 1 },
        islie     => { _when => 'out', anybool => 1 },
        overruled => { _when => 'out', anybool => 1 },
        othnotes  => { _when => 'out' },
        hidden    => { _when => 'out', anybool => 1 },
        locked    => { _when => 'out', anybool => 1 },
        applicable => { _when => 'out', anybool => 1 },
    } },
    mod   => { _when => 'out', anybool => 1 },
};

my $FORM_IN  = form_compile in  => $FORM;
my $FORM_OUT = form_compile out => $FORM;


sub can_tag { auth->permTagmod || (auth->permTag && !global_settings->{lockdown_edit}) }


elm_api Tagmod => $FORM_OUT, $FORM_IN, sub {
    my($id, $tags) = $_[0]->@{'id', 'tags'};
    return elm_Unauth if !can_tag;

    $tags = [ grep $_->{vote}, @$tags ];
    $_->{overrule} = 0 for auth->permTagmod ? () : @$tags;

    # Weed out invalid/deleted/non-applicable tags.
    # Voting on non-applicable tags is still allowed if there are existing votes for this tag on this VN.
    enrich_merge id => sql('
        SELECT tag AS id, 1 as exists FROM tags_vn WHERE vid =', \$id, '
        UNION
        SELECT id, 1 as exists FROM tags WHERE NOT (hidden AND locked) AND applicable AND id IN'
    ), $tags;
    $tags = [ grep $_->{exists}, @$tags ];

    # Find out if any of these tags are being overruled
    enrich_merge id => sub { sql 'SELECT tag AS id, bool_or(ignore) as overruled FROM tags_vn WHERE vid =', \$id, 'AND tag IN', $_, 'GROUP BY tag' }, $tags;

    # Delete tag votes not in $tags
    tuwf->dbExeci('DELETE FROM tags_vn WHERE uid =', \auth->uid, 'AND vid =', \$id, @$tags ? ('AND tag NOT IN', [ map $_->{id}, @$tags ]) : ());

    # Add & update tags
    for(@$tags) {
        my $row = { uid => auth->uid, vid => $id, tag => $_->{id}, vote => $_->{vote}, notes => $_->{notes}
                  , spoiler => $_->{spoil}, lie => $_->{lie}, ignore => ($_->{overruled} && !$_->{overrule})?1:0
                  };
        tuwf->dbExeci('INSERT INTO tags_vn', $row, 'ON CONFLICT (uid, tag, vid) DO UPDATE SET', $row);
        tuwf->dbExeci('UPDATE tags_vn SET ignore = TRUE WHERE uid IS DISTINCT FROM (', \auth->uid, ') AND vid =', \$id, 'AND tag =', \$_->{id}) if $_->{overrule};
    }

    # Make sure to reset the ignore flag when a moderator removes an overruled vote.
    # (i.e. look for tags where *all* votes are on ignore)
    tuwf->dbExeci('UPDATE tags_vn tv SET ignore = FALSE WHERE NOT EXISTS(SELECT 1 FROM tags_vn tvi WHERE tvi.tag = tv.tag AND tvi.vid = tv.vid AND NOT tvi.ignore) AND vid =', \$id) if auth->permTagmod;

    tuwf->dbExeci(select => sql_func tag_vn_calc => \$id);
    elm_Success
};


TUWF::get qr{/$RE{vid}/tagmod}, sub {
    my $v = dbobj tuwf->capture('id');
    return tuwf->resNotFound if !$v->{id} || (!auth->permDbmod && $v->{entry_hidden});
    return tuwf->resDenied if !can_tag;

    my $tags = tuwf->dbAlli('
        SELECT t.id, t.name, t.cat, t.hidden, t.locked, t.applicable
             , tv.count, tv.overruled
             , coalesce(td.rating, 0) AS rating, coalesce(td.spoiler, t.defaultspoil) AS spoiler, coalesce(td.islie, false) AS islie
          FROM (SELECT tag, count(*) AS count, bool_or(ignore) as overruled FROM tags_vn WHERE vid =', \$v->{id}, ' GROUP BY tag) tv
          JOIN tags t ON t.id = tv.tag
          LEFT JOIN (
            SELECT tv.tag
                 , COALESCE(AVG(tv.vote) filter (where tv.vote > 0), 1+1+1) * SUM(sign(tv.vote)) / COUNT(tv.vote) AS rating
                 , AVG(tv.spoiler) AS spoiler
                 , count(lie) filter(where lie) > 0 AND count(lie) filter (where lie) >= count(lie) filter(where not lie) AS islie
              FROM tags_vn tv
              JOIN tags t ON t.id = tv.tag
              LEFT JOIN users u ON u.id = tv.uid
             WHERE NOT tv.ignore AND (u.id IS NULL OR u.perm_tag) AND tv.vid =', \$v->{id}, '
             GROUP BY tv.tag
          ) td ON td.tag = tv.tag
         ORDER BY t.name'
    );
    enrich_merge id => sub { sql 'SELECT tag AS id, vote, spoiler AS spoil, lie, ignore, notes FROM tags_vn WHERE', { uid => auth->uid, vid => $v->{id} } }, $tags;
    enrich othnotes => id => tag => sub {
        sql('SELECT tv.tag, ', sql_user(), ', tv.notes FROM tags_vn tv JOIN users u ON u.id = tv.uid WHERE tv.notes <> \'\' AND uid IS DISTINCT FROM (', \auth->uid, ') AND vid=', \$v->{id})
    }, $tags;

    for(@$tags) {
        $_->{vote} //= 0;
        $_->{spoil} //= undef;
        $_->{lie} //= undef;
        $_->{notes} //= '';
        $_->{overrule} = $_->{vote} && !$_->{ignore} && $_->{overruled};
        $_->{othnotes} = join "\n", map user_displayname($_).': '.$_->{notes}, $_->{othnotes}->@*;
    }

    framework_ title => "Edit tags for $v->{title}[1]", dbobj => $v, tab => 'tagmod', sub {
        elm_ 'Tagmod' => $FORM_OUT, { id => $v->{id}, title => $v->{title}[1], tags => $tags, mod => auth->permTagmod };
    };
};

1;
