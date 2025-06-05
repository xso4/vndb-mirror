package VNWeb::VN::Tagmod;

use VNWeb::Prelude;
use VNWeb::TT::Lib;


my $FORM = form_compile {
    id    => { vndbid => 'v' },
    title => { },
    mod   => { anybool => 1 },
    tags  => { sort_keys => 'id', aoh => {
        id        => { vndbid => 'g' },
        vote      => { int => 1, enum => [ -3..3 ] },
        spoil     => { default => undef, uint => 1, enum => [ 0..2 ] },
        lie       => { undefbool => 1 },
        overrule  => { anybool => 1 },
        notes     => { default => '', sl => 1, maxlength => 1000 },
        cat       => {},
        name      => {},
        rating    => { default => undef, num => 1 },
        tagscore  => { default => undef },
        count     => { default => 0, uint => 1 },
        spoiler   => { default => undef },
        islie     => { anybool => 1 },
        overruled => { anybool => 1 },
        othnotes  => { default => '' },
        hidden    => { anybool => 1 },
        locked    => { anybool => 1 },
        applicable=> { anybool => 1 },
    } },
};


sub can_tag { auth->permTagmod || (auth->permTag && !global_settings->{lockdown_edit}) }


js_api Tagmod => $FORM, sub($data) {
    my($id, $tags) = $data->@{'id', 'tags'};
    fu->denied if !can_tag;

    $tags = [ grep $_->{vote}, @$tags ];
    $_->{overrule} = 0 for auth->permTagmod ? () : @$tags;

    # Weed out invalid/deleted/non-applicable tags.
    # Voting on non-applicable tags is still allowed if there are existing votes for this tag on this VN.
    fu->enrich(set => 'exists', SQL('
        SELECT tag FROM tags_vn WHERE vid =', $id, '
        UNION
        SELECT id FROM tags WHERE NOT (hidden AND locked) AND applicable AND id'
    ), $tags);
    $tags = [ grep $_->{exists}, @$tags ];

    # Find out if any of these tags are being overruled
    fu->enrich(set => 'overruled', sub { SQL 'SELECT tag, bool_or(ignore) FROM tags_vn WHERE vid =', $id, 'AND tag', IN $_, 'GROUP BY tag' }, $tags);

    # Delete tag votes not in $tags
    fu->SQL('DELETE FROM tags_vn WHERE uid =', auth->uid, 'AND vid =', $id, @$tags ? ('AND NOT tag', IN [ map $_->{id}, @$tags ]) : ())->exec;

    # Add & update tags
    for(@$tags) {
        my $row = { uid => auth->uid, vid => $id, tag => $_->{id}, vote => $_->{vote}, notes => $_->{notes}
                  , spoiler => $_->{spoil}, lie => $_->{lie}, ignore => ($_->{overruled} && !$_->{overrule})?1:0
                  };
        fu->SQL('INSERT INTO tags_vn', VALUES($row), 'ON CONFLICT (uid, tag, vid) DO UPDATE', SET $row)->exec;
        fu->SQL('UPDATE tags_vn SET ignore = TRUE WHERE uid IS DISTINCT FROM', auth->uid, 'AND vid =', $id, 'AND tag =', $_->{id})->exec if $_->{overrule};
    }

    # Make sure to reset the ignore flag when a moderator removes an overruled vote.
    # (i.e. look for tags where *all* votes are on ignore)
    fu->SQL('UPDATE tags_vn tv SET ignore = FALSE WHERE NOT EXISTS(SELECT 1 FROM tags_vn tvi WHERE tvi.tag = tv.tag AND tvi.vid = tv.vid AND NOT tvi.ignore) AND vid =', $id)->exec if auth->permTagmod;

    fu->sql('SELECT tag_vn_calc($1)', $id)->exec;
    +{ _redir => "/$id/tagmod" }
};


FU::get qr{/$RE{vid}/tagmod}, sub($id) {
    my $v = dbobj $id;
    fu->notfound if !$v->{id} || (!auth->permDbmod && $v->{entry_hidden});
    fu->denied if !can_tag;

    my $tags = fu->SQL('
        SELECT t.id, t.name, t.cat, t.hidden, t.locked, t.applicable
             , tv.count, tv.overruled
             , coalesce(td.rating, 0) AS rating, coalesce(td.spoiler, t.defaultspoil) AS spoiler, coalesce(td.islie, false) AS islie
          FROM (SELECT tag, count(*) AS count, bool_or(ignore) as overruled FROM tags_vn WHERE vid =', $v->{id}, ' GROUP BY tag) tv
          JOIN tags t ON t.id = tv.tag
          LEFT JOIN (
            SELECT tv.tag
                 , COALESCE(AVG(tv.vote) filter (where tv.vote > 0), 1+1+1) * SUM(sign(tv.vote)) / COUNT(tv.vote) AS rating
                 , AVG(tv.spoiler)::float AS spoiler
                 , count(lie) filter(where lie) > 0 AND count(lie) filter (where lie) >= count(lie) filter(where not lie) AS islie
              FROM tags_vn tv
              JOIN tags t ON t.id = tv.tag
              LEFT JOIN users u ON u.id = tv.uid
             WHERE NOT tv.ignore AND (u.id IS NULL OR u.perm_tag) AND tv.vid =', $v->{id}, '
             GROUP BY tv.tag
          ) td ON td.tag = tv.tag
         ORDER BY t.name'
    )->allh;
    fu->enrich(merge => 1, sub { SQL 'SELECT tag, vote, spoiler AS spoil, lie, ignore, notes FROM tags_vn', WHERE { uid => auth->uid, vid => $v->{id} } }, $tags);
    fu->enrich(aoh => 'othnotes', sub {
        SQL('SELECT tv.tag, ', USER, ', tv.notes FROM tags_vn tv JOIN users u ON u.id = tv.uid WHERE tv.notes <> \'\' AND uid IS DISTINCT FROM', auth->uid, 'AND vid=', $v->{id})
    }, $tags);

    for(@$tags) {
        $_->{vote} //= 0;
        $_->{spoil} //= undef;
        $_->{lie} //= undef;
        $_->{notes} //= '';
        $_->{tagscore} = fragment sub {
            tagscore_ $_->{rating};
            i_ class => $_->{overruled} ? 'grayedout' : undef, " ($_->{count})";
        };
        $_->{spoiler} = sprintf '%.2f', $_->{spoiler};
        $_->{overrule} = $_->{vote} && !$_->{ignore} && $_->{overruled};
        $_->{othnotes} = join "\n", map user_displayname($_).': '.$_->{notes}, $_->{othnotes}->@*;
    }

    framework_ title => "Edit tags for $v->{title}[1]", dbobj => $v, tab => 'tagmod', sub {
        article_ sub {
            h1_ "Edit tags for $v->{title}[1]";
            p_ sub {
                txt_ 'This is where you can add tags to the visual novel and vote on the existing tags.'; br_;
                txt_ "Don't forget to also select the appropriate spoiler option for each tag."; br_;
                txt_ 'For more information, check out the ';
                a_ href => '/d10', target => '_blank', 'guidelines'; txt_ '.';
            };
            div_ widget(Tagmod => $FORM, { id => $v->{id}, title => $v->{title}[1], tags => $tags, mod => auth->permTagmod }), '';
        };
    };
};

1;
