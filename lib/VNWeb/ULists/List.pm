package VNWeb::ULists::Main;

use VNWeb::Prelude;
use VNWeb::ULists::Lib;
use VNWeb::Releases::Lib;


my $TABLEOPTS = tableopts
    title => {
        name => 'Title',
        sort_sql => 'v.sorttitle',
        sort_id => 0,
        compat => 'title',
        sort_default => 'asc',
    },
    voted => {
        name => 'Vote date',
        sort_sql => 'uv.vote_date',
        sort_id => 1,
        sort_num => 1,
        vis_id => 0,
        compat => 'voted'
    },
    vote => {
        name => 'Vote',
        sort_sql => 'uv.vote',
        sort_id => 2,
        sort_num => 1,
        vis_id => 1,
        compat => 'vote'
    },
    rating => {
        name => 'Rating',
        sort_sql => 'v.c_rating',
        sort_id => 3,
        sort_num => 1,
        vis_id => 2,
        compat => 'rating'
    },
    label => {
        name => 'Labels',
        sort_sql => sql('ARRAY(SELECT ul.label FROM ulist_vns_labels uvl JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl WHERE uvl.uid = uv.uid AND uvl.vid = uv.vid AND uvl.lbl <> ', \7, ')'),
        sort_id => 4,
        vis_id => 3,
        compat => 'label'
    },
    added => {
        name => 'Added',
        sort_sql => 'uv.added',
        sort_id => 5,
        sort_num => 1,
        vis_id => 4,
        compat => 'added'
    },
    modified => {
        name => 'Modified',
        sort_sql => 'uv.lastmod',
        sort_id => 6,
        sort_num => 1,
        vis_id => 5,
        compat => 'modified'
    },
    started => {
        name => 'Start date',
        sort_sql => 'uv.started',
        sort_id => 7,
        sort_num => 1,
        vis_id => 6,
        compat => 'started'
    },
    finished => {
        name => 'Finish date',
        sort_sql => 'uv.finished',
        sort_id => 8,
        sort_num => 1,
        vis_id => 7,
        compat => 'finished'
    },
    rel => {
        name => 'Release date',
        sort_sql => 'v.c_released',
        sort_id => 9,
        sort_num => 1,
        vis_id => 8,
        compat => 'rel'
    };


sub opt {
    my($u, $filtlabels) = @_;

    # Note that saved defaults may still use the old query format, which is
    #   { s => $sort_column, o => $order, c => [$visible_columns] }
    my sub load { my $o = $u->{"ulist_$_[0]"}; ($o && eval { JSON::XS->new->decode($o) } or {})->%* };

    state $s_default  = tuwf->compile({ tableopts => $TABLEOPTS })->validate(undef)->data;
    state $s_vnlist   = $s_default->sort_param(title => 'a')->vis_param(qw/label vote added started finished/)->query_encode;
    state $s_votes    = $s_default->sort_param(voted => 'd')->vis_param(qw/vote voted/)->query_encode;
    state $s_wishlist = $s_default->sort_param(title => 'a')->vis_param(qw/label added/)->query_encode;

    my $opt =
        # Presets
        tuwf->reqGet('vnlist')   ? { mul => 0, p => 1, l => [1,2,3,4,7,-1,0], s => $s_vnlist,   load 'vnlist' } :
        tuwf->reqGet('votes')    ? { mul => 0, p => 1, l => [7],              s => $s_votes,    load 'votes'  } :
        tuwf->reqGet('wishlist') ? { mul => 0, p => 1, l => [5],              s => $s_wishlist, load 'wish'   } :
        # Full options
        tuwf->validate(get =>
            p => { upage => 1 },
            ch=> { onerror => undef, enum => [ 'a'..'z', 0 ] },
            q => { onerror => undef },
            %VNWeb::ULists::Elm::SAVED_OPTS,
            # Compat for old URLs
            o => { onerror => undef, enum => ['a', 'd'] },
            c => { onerror => undef, type => 'array', scalar => 1, values => { enum => [qw[ label vote voted added modified started finished rel rating ]] } },
        )->data;

    $opt->{s} .= "/$opt->{o}" if $opt->{o};
    $opt->{s} = tuwf->compile({ tableopts => $TABLEOPTS })->validate($opt->{s})->data;
    $opt->{s} = $opt->{s}->vis_param($opt->{c}->@*) if $opt->{c};
    delete $opt->{o};
    delete $opt->{c};

    # $labels only includes labels we are allowed to see, getting rid of any labels in 'l' that aren't in $labels ensures we only filter on visible labels
    my %accessible_labels = map +($_->{id}, 1), @$filtlabels;
    my %opt_l = map +($_, 1), grep $accessible_labels{$_}, $opt->{l}->@*;
    %opt_l = %accessible_labels if !keys %opt_l;
    $opt->{l} = keys %opt_l == keys %accessible_labels ? [] : [ sort keys %opt_l ];

    ($opt, \%opt_l)
}


sub filters_ {
    my($own, $filtlabels, $opt, $opt_labels, $url) = @_;

    my sub lblfilt_ {
        input_ type => 'checkbox', name => 'l', value => $_->{id}, id => "form_l$_->{id}", tabindex => 10, $opt_labels->{$_->{id}} ? (checked => 'checked') : ();
        label_ for => "form_l$_->{id}", "$_->{label} ";
        txt_ " ($_->{count})";
    }

    input_ type => 'hidden', name => 'ch', value => $opt->{ch} if defined $opt->{ch};
    p_ class => 'labelfilters', sub {
        input_ type => 'text', class => 'text', name => 'q', value => $opt->{q}||'', style => 'width: 500px', placeholder => 'Search', tabindex => 10;
        br_;
        # XXX: Rather silly that everything in this form is a form element except for the alphabet filter. Meh, behavior seems intuitive enough.
        span_ class => 'browseopts', sub {
            a_ href => $url->(ch => $_, p => undef), ($_//'') eq ($opt->{ch}//'') ? (class => 'optselected') : (), !defined($_) ? 'ALL' : $_ ? uc $_ : '#'
                for (undef, 'a'..'z', 0);
        };
        br_;
        span_ class => 'linkradio', sub {
            join_ sub { em_ ' / ' }, \&lblfilt_, grep $_->{id} < 10, @$filtlabels;

            span_ class => 'hidden', sub {
                em_ ' || ';
                input_ type => 'checkbox', name => 'mul', value => 1, id => 'form_l_multi', tabindex => 10, $opt->{mul} ? (checked => 'checked') : ();
                label_ for => 'form_l_multi', 'Multi-select';
            };
            debug_ $filtlabels;
        };
        my @cust = grep $_->{id} >= 10, @$filtlabels;
        if(@cust) {
            br_;
            span_ class => 'linkradio', sub {
                join_ sub { em_ ' / ' }, \&lblfilt_, @cust;
            }
        }
        br_;
        input_ type => 'submit', class => 'submit', tabindex => 10, value => 'Update filters';
        input_ type => 'button', class => 'submit', tabindex => 10, id => 'managelabels', value => 'Manage labels' if $own;
        input_ type => 'button', class => 'submit', tabindex => 10, id => 'savedefault', value => 'Save as default' if $own;
        input_ type => 'button', class => 'submit', tabindex => 10, id => 'exportlist', value => 'Export' if $own;
    };
}


sub vn_ {
    my($uid, $own, $opt, $n, $v, $labels) = @_;
    tr_ mkclass(odd => $n % 2 == 0), id => "ulist_tr_$v->{id}", sub {
        my %labels = map +($_,1), $v->{labels}->@*;

        td_ class => 'tc1', sub {
            input_ type => 'checkbox', class => 'checkhidden', 'x-checkall' => 'collapse_vid', id => 'collapse_vid'.$v->{id}, value => 'collapsed_vid'.$v->{id};
            label_ for => 'collapse_vid'.$v->{id}, sub {
                my $obtained = grep $_->{status} == 2, $v->{rels}->@*;
                my $total = $v->{rels}->@*;
                b_ id => 'ulist_relsum_'.$v->{id},
                    mkclass(done => $total && $obtained == $total, todo => $obtained < $total, neutral => 1),
                    sprintf '%d/%d', $obtained, $total;
                if($own) {
                    my $public = List::Util::any { $labels{$_->{id}} && !$_->{private} } @$labels;
                    my $publicLabel = List::Util::any { $_->{id} != 7 && $labels{$_->{id}} && !$_->{private} } @$labels;
                    span_ mkclass(invisible => !$public),
                          id              => 'ulist_public_'.$v->{id},
                          'data-publabel' => !!$publicLabel,
                          'data-voted'    => !!$labels{7},
                          title           => 'This item is public', ' 👁';
                }
            };
        };

        td_ class => 'tc_voted',    $v->{vote_date} ? fmtdate $v->{vote_date}, 'compact' : '-' if $opt->{s}->vis('voted');

        td_ mkclass(tc_vote => 1, compact => $own, stealth => $own), sub {
            txt_ fmtvote $v->{vote} if !$own;
            elm_ 'UList.VoteEdit' => $VNWeb::ULists::Elm::VNVOTE, { uid => $uid, vid => $v->{id}, vote => fmtvote($v->{vote}) }, sub {
                div_ @_, fmtvote $v->{vote}
            } if $own && ($v->{vote} || sprintf('%08d', $v->{c_released}||0) < strftime '%Y%m%d', gmtime);
        } if $opt->{s}->vis('vote');

        td_ class => 'tc_rating', sub {
            txt_ sprintf '%.2f', ($v->{c_rating}||0)/100;
            b_ class => 'grayedout', sprintf ' (%d)', $v->{c_votecount};
        } if $opt->{s}->vis('rating');

        td_ class => 'tc_labels', sub {
            my @l = grep $labels{$_->{id}} && $_->{id} != 7, @$labels;
            my $txt = @l ? join ', ', map $_->{label}, @l : '-';
            if($own) {
                elm_ 'UList.LabelEdit' => $VNWeb::ULists::Elm::VNLABELS_OUT, { vid => $v->{id}, selected => [ grep $_ != 7, $v->{labels}->@* ] }, sub {
                    div_ @_, $txt;
                };
            } else {
                txt_ $txt;
            }
        } if $opt->{s}->vis('label');

        td_ class => 'tc_title', sub {
            a_ href => "/$v->{id}", title => $v->{alttitle}||$v->{title}, shorten $v->{title}, 70;
            b_ class => 'grayedout', id => 'ulist_notes_'.$v->{id}, $v->{notes} if $v->{notes} || $own;
        };

        td_ class => 'tc_added',    fmtdate $v->{added},     'compact' if $opt->{s}->vis('added');
        td_ class => 'tc_modified', fmtdate $v->{lastmod},   'compact' if $opt->{s}->vis('modified');

        td_ class => 'tc_started', sub {
            txt_ $v->{started}||'' if !$own;
            elm_ 'UList.DateEdit' => $VNWeb::ULists::Elm::VNDATE, { uid => $uid, vid => $v->{id}, date => $v->{started}||'', start => 1 }, sub {
                div_ @_, $v->{started}||''
            } if $own;
        } if $opt->{s}->vis('started');

        td_ class => 'tc_finished', sub {
            txt_ $v->{finished}||'' if !$own;
            elm_ 'UList.DateEdit' => $VNWeb::ULists::Elm::VNDATE, { uid => $uid, vid => $v->{id}, date => $v->{finished}||'', start => 0 }, sub {
                div_ @_, $v->{finished}||''
            } if $own;
        } if $opt->{s}->vis('finished');

        td_ class => 'tc_rel', sub { rdate_ $v->{c_released} } if $opt->{s}->vis('rel');
    };

    tr_ mkclass(hidden => 1, 'collapsed_vid'.$v->{id} => 1, odd => $n % 2 == 0), sub {
        td_ colspan => 7, class => 'tc_opt', sub {
            my $relstatus = [ map $_->{status}, $v->{rels}->@* ];
            elm_ 'UList.Opt' => $VNWeb::ULists::Elm::VNOPT, { own => $own, uid => $uid, vid => $v->{id}, notes => $v->{notes}, rels => $v->{rels}, relstatus => $relstatus };
        };
    };
}


sub listing_ {
    my($uid, $own, $opt, $labels, $url) = @_;

    my @l = grep $_ > 0 && $_ != 7, $opt->{l}->@*;
    my($unlabeled) = grep $_ == -1, $opt->{l}->@*;
    my($voted) = grep $_ == 7, $opt->{l}->@*;

    my @where_vns = (
              @l ? sql('uv.vid IN(SELECT vid FROM ulist_vns_labels WHERE uid =', \$uid, 'AND lbl IN', \@l, ')') : (),
      $unlabeled ? sql('NOT EXISTS(SELECT 1 FROM ulist_vns_labels WHERE uid =', \$uid, 'AND vid = uv.vid AND lbl <> ', \7, ')') : (),
          $voted ? sql('uv.vote IS NOT NULL') : ()
    );

    my $where = sql_and
        sql('uv.uid =', \$uid),
        !$own ? sql('uv.vid IN(SELECT vid FROM ulist_vns_labels WHERE uid =', \$uid, 'AND lbl IN(SELECT id FROM ulist_labels WHERE uid =', \$uid, 'AND NOT private))') : (),
        @where_vns ? sql_or(@where_vns) : (),
        $opt->{q} ? sql 'v.c_search LIKE ALL (search_query(', \$opt->{q}, '))' : (),
        defined($opt->{ch}) ? sql 'match_firstchar(v.sorttitle, ', \$opt->{ch}, ')' : ();

    my $count = tuwf->dbVali('SELECT count(*) FROM ulist_vns uv JOIN vnt v ON v.id = uv.vid WHERE', $where);

    my $lst = tuwf->dbPagei({ page => $opt->{p}, results => $opt->{s}->results },
        'SELECT v.id, v.title, v.alttitle, uv.vote, uv.notes, uv.started, uv.finished, v.c_rating, v.c_votecount, v.c_released
              ,', sql_totime('uv.added'), ' as added
              ,', sql_totime('uv.lastmod'), ' as lastmod
              ,', sql_totime('uv.vote_date'), ' as vote_date
           FROM ulist_vns uv
           JOIN vnt v ON v.id = uv.vid
          WHERE', $where, '
          ORDER BY', $opt->{s}->sql_order(), 'NULLS LAST, v.sorttitle'
    );

    enrich_flatten labels => id => vid => sql('SELECT vid, lbl FROM ulist_vns_labels WHERE uid =', \$uid, 'AND vid IN'), $lst;

    enrich rels => id => vid => sub { sql '
        SELECT rv.vid, r.id, rl.status, rv.rtype
          FROM rlists rl
          JOIN releasest r ON rl.rid = r.id
          JOIN releases_vn rv ON rv.id = r.id
         WHERE rl.uid =', \$uid, '
           AND rv.vid IN', $_, '
         ORDER BY r.released, r.sorttitle, r.id'
    }, $lst;
    enrich_release_elm map $_->{rels}, @$lst;

    paginate_ $url, $opt->{p}, [$count, $opt->{s}->results], 't', sub { $opt->{s}->elm_ };
    div_ class => 'mainbox browse ulist', sub {
        table_ sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub {
                    # TODO: these checkboxes shouldn't be included in the query string
                    input_ type => 'checkbox', class => 'checkall', 'x-checkall' => 'collapse_vid', id => 'collapse_vid';
                    label_ for => 'collapse_vid', sub { txt_ 'Opt' };
                };
                td_ class => 'tc_voted',    sub { txt_ 'Vote date';   sortable_ 'voted',    $opt, $url } if $opt->{s}->vis('voted');
                td_ class => 'tc_vote',     sub { txt_ 'Vote';        sortable_ 'vote',     $opt, $url } if $opt->{s}->vis('vote');
                td_ class => 'tc_rating',   sub { txt_ 'Rating';      sortable_ 'rating',   $opt, $url } if $opt->{s}->vis('rating');
                td_ class => 'tc_labels',   sub { txt_ 'Labels';      sortable_ 'label',    $opt, $url } if $opt->{s}->vis('label');
                td_ class => 'tc_title',    sub { txt_ 'Title';       sortable_ 'title',    $opt, $url; debug_ $lst };
                td_ class => 'tc_added',    sub { txt_ 'Added';       sortable_ 'added',    $opt, $url } if $opt->{s}->vis('added');
                td_ class => 'tc_modified', sub { txt_ 'Modified';    sortable_ 'modified', $opt, $url } if $opt->{s}->vis('modified');
                td_ class => 'tc_started',  sub { txt_ 'Start date';  sortable_ 'started',  $opt, $url } if $opt->{s}->vis('started');
                td_ class => 'tc_finished', sub { txt_ 'Finish date'; sortable_ 'finished', $opt, $url } if $opt->{s}->vis('finished');
                td_ class => 'tc_rel',      sub { txt_ 'Release date';sortable_ 'rel',      $opt, $url } if $opt->{s}->vis('rel');
            }};
            vn_ $uid, $own, $opt, $_, $lst->[$_], $labels for (0..$#$lst);
        };
    };
    paginate_ $url, $opt->{p}, [$count, $opt->{s}->results], 'b';
}


# TODO: Ability to add VNs from this page
TUWF::get qr{/$RE{uid}/ulist}, sub {
    my $u = tuwf->dbRowi('
        SELECT u.id,', sql_user(), ', ulist_votes, ulist_vnlist, ulist_wish
          FROM users u JOIN users_prefs up ON up.id = u.id
         WHERE u.id =', \tuwf->capture('id'));
    return tuwf->resNotFound if !$u->{id};

    my $own = ulists_own $u->{id};

    # Visible and selectable labels
    my $labels = tuwf->dbAlli(
        'SELECT l.id, l.label, l.private, count(vl.vid) as count, null as delete
           FROM ulist_labels l LEFT JOIN ulist_vns_labels vl ON vl.uid = l.uid AND vl.lbl = l.id
          WHERE', { 'l.uid' => $u->{id}, $own ? () : ('l.private' => 0) },
         'GROUP BY l.id, l.label, l.private
          ORDER BY CASE WHEN l.id < 10 THEN l.id ELSE 10 END, l.label'
    );

    # All visible labels that can be filtered on, including "virtual" labels like 'No label'
    my $filtlabels = [
        @$labels,
        # Consider label 7 (Voted) a virtual label if it's set to private.
        !grep($_->{id} == 7, @$labels) ? {
            id => 7, label => 'Voted', count => tuwf->dbVali(
                'SELECT count(*)
                   FROM ulist_vns uv
                  WHERE uv.vote IS NOT NULL AND EXISTS(SELECT 1 FROM ulist_vns_labels uvl JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl WHERE uvl.uid = uv.uid AND uvl.vid = uv.vid AND NOT ul.private)
                    AND uid =', \$u->{id}
            )
        } : (),
        $own ? {
            id => -1, label => 'No label', count => tuwf->dbVali(
                'SELECT count(*)
                   FROM ulist_vns uv
                  WHERE NOT EXISTS(SELECT 1 FROM ulist_vns_labels uvl WHERE uvl.uid = uv.uid AND uvl.vid = uv.vid AND uvl.lbl <>', \7, ')
                    AND uid =', \$u->{id}
            )
        } : (),
    ];

    my($opt, $opt_labels) = opt $u, $filtlabels;
    my sub url { '?'.query_encode %$opt, @_ }

    # This page has 3 user tabs: list, wish and votes; Select the appropriate active tab based on label filters.
    my $num_core_labels = grep $_ < 10, keys %$opt_labels;
    my $tab = $num_core_labels == 1 && $opt_labels->{7} ? 'votes'
            : $num_core_labels == 1 && $opt_labels->{5} ? 'wish' : 'list';

    my $title = $own ? 'My list' : user_displayname($u)."'s list";
    framework_ title => $title, dbobj => $u, tab => $tab, js => 1,
        $own ? ( pagevars => {
            uid         => $u->{id},
            labels      => $VNWeb::ULists::Elm::LABELS->analyze->{keys}{labels}->coerce_for_json($labels),
            voteprivate => (map \($_->{private}?1:0), grep $_->{id} == 7, @$labels),
        } ) : (),
    sub {
        my $empty = !grep $_->{count}, @$filtlabels;
        form_ method => 'get', sub {
            div_ class => 'mainbox', sub {
                h1_ $title;
                if($empty) {
                    p_ $own
                        ? 'Your list is empty! You can add visual novels to your list from the visual novel pages.'
                        : user_displayname($u).' does not have any visible visual novels in their list.';
                } else {
                    filters_ $own, $filtlabels, $opt, $opt_labels, \&url;
                    elm_ 'UList.ManageLabels' if $own;
                    elm_ 'UList.SaveDefault', $VNWeb::ULists::Elm::SAVED_OPTS_OUT, {
                        uid => $u->{id},
                        opts => { l => $opt->{l}, mul => $opt->{mul}, s => $opt->{s}->query_encode() },
                    } if $own;
                    div_ class => 'hidden exportlist', sub {
                        b_ 'Export your list';
                        br_;
                        txt_ 'This function will export all visual novels and releases in your list, even those marked as private ';
                        txt_ '(there is currently no import function, more export options may be added later).';
                        br_;
                        br_;
                        a_ href => "/$u->{id}/list-export/xml", "Download XML export.";
                    } if $own;
                }
            };
            listing_ $u->{id}, $own, $opt, $labels, \&url if !$empty;
        }
    };
};



# Redirects for old URLs
TUWF::get qr{/$RE{uid}/votes}, sub { tuwf->resRedirect("/".tuwf->capture('id').'/ulist?votes=1', 'perm') };
TUWF::get qr{/$RE{uid}/list},  sub { tuwf->resRedirect("/".tuwf->capture('id').'/ulist?vnlist=1', 'perm') };
TUWF::get qr{/$RE{uid}/wish},  sub { tuwf->resRedirect("/".tuwf->capture('id').'/ulist?wishlist=1', 'perm') };


1;
