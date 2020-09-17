package VNWeb::ULists::Main;

use VNWeb::Prelude;
use VNWeb::ULists::Lib;
use VNWeb::Releases::Lib;


sub opt {
    my($u, $filtlabels) = @_;

    my sub load { my $o = $u->{"ulist_$_[0]"}; ($o && eval { JSON::XS->new->decode($o) } or {})->%* };

    my $opt =
        # Presets
        tuwf->reqGet('vnlist')   ? { mul => 0, p => 1, l => [1,2,3,4,7,-1,0], s => 'title', o => 'a', c => [qw/label vote added started finished/], load 'vnlist' } :
        tuwf->reqGet('votes')    ? { mul => 0, p => 1, l => [7],              s => 'voted', o => 'd', c => [qw/vote voted/], load 'votes' } :
        tuwf->reqGet('wishlist') ? { mul => 0, p => 1, l => [5],              s => 'title', o => 'a', c => [qw/label added/], load 'wish' } :
        # Full options
        tuwf->validate(get =>
            p => { upage => 1 },
            ch=> { onerror => undef, enum => [ 'a'..'z', 0 ] },
            q => { onerror => undef },
            %VNWeb::ULists::Elm::SAVED_OPTS
        )->data;

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

    form_ method => 'get', sub {
        input_ type => 'hidden', name => 's', value => $opt->{s};
        input_ type => 'hidden', name => 'o', value => $opt->{o};
        input_ type => 'hidden', name => 'ch', value => $opt->{ch} if defined $opt->{ch};
        input_ type => 'hidden', name => 'c', value => $_ for $opt->{c}->@*;
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
    };
}


sub vn_ {
    my($uid, $own, $opt, $n, $v, $labels) = @_;
    tr_ mkclass(odd => $n % 2 == 0), id => "ulist_tr_$v->{id}", sub {
        my %labels = map +($_,1), $v->{labels}->@*;

        td_ class => 'tc1', sub {
            input_ type => 'checkbox', class => 'checkhidden', name => 'collapse_vid', id => 'collapse_vid'.$v->{id}, value => 'collapsed_vid'.$v->{id};
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

        td_ class => 'tc_voted',    $v->{vote_date} ? fmtdate $v->{vote_date}, 'compact' : '-' if in voted => $opt->{c};

        td_ mkclass(tc_vote => 1, compact => $own, stealth => $own), sub {
            txt_ fmtvote $v->{vote} if !$own;
            elm_ 'UList.VoteEdit' => $VNWeb::ULists::Elm::VNVOTE, { uid => $uid, vid => $v->{id}, vote => fmtvote($v->{vote}) }, fmtvote $v->{vote}
                if $own && ($v->{vote} || sprintf('%08d', $v->{c_released}||0) < strftime '%Y%m%d', gmtime);
        } if in vote => $opt->{c};

        td_ class => 'tc_rating', sub {
            txt_ sprintf '%.2f', ($v->{c_rating}||0)/10;
            b_ class => 'grayedout', sprintf ' (%d)', $v->{c_votecount};
        } if in rating => $opt->{c};

        td_ class => 'tc_labels', sub {
            my @l = grep $labels{$_->{id}} && $_->{id} != 7, @$labels;
            my $txt = @l ? join ', ', map $_->{label}, @l : '-';
            if($own) {
                elm_ 'UList.LabelEdit' => $VNWeb::ULists::Elm::VNLABELS_OUT, { vid => $v->{id}, selected => [ grep $_ != 7, $v->{labels}->@* ] }, $txt;
            } else {
                txt_ $txt;
            }
        } if in label => $opt->{c};

        td_ class => 'tc_title', sub {
            a_ href => "/v$v->{id}", title => $v->{original}||$v->{title}, shorten $v->{title}, 70;
            b_ class => 'grayedout', id => 'ulist_notes_'.$v->{id}, $v->{notes} if $v->{notes} || $own;
        };

        td_ class => 'tc_added',    fmtdate $v->{added},     'compact' if in added    => $opt->{c};
        td_ class => 'tc_modified', fmtdate $v->{lastmod},   'compact' if in modified => $opt->{c};

        td_ class => 'tc_started', sub {
            txt_ $v->{started}||'' if !$own;
            elm_ 'UList.DateEdit' => $VNWeb::ULists::Elm::VNDATE, { uid => $uid, vid => $v->{id}, date => $v->{started}||'', start => 1 }, $v->{started}||'' if $own;
        } if in started => $opt->{c};

        td_ class => 'tc_finished', sub {
            txt_ $v->{finished}||'' if !$own;
            elm_ 'UList.DateEdit' => $VNWeb::ULists::Elm::VNDATE, { uid => $uid, vid => $v->{id}, date => $v->{finished}||'', start => 0 }, $v->{finished}||'' if $own;
        } if in finished => $opt->{c};

        td_ class => 'tc_rel', sub { rdate_ $v->{c_released} } if in rel => $opt->{c};
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
        $opt->{q} ? map sql('v.c_search like', \"%$_%"), normalize_query $opt->{q} : (),
        defined($opt->{ch}) && $opt->{ch} ? sql('LOWER(SUBSTR(v.title, 1, 1)) =', \$opt->{ch}) : (),
        defined($opt->{ch}) && !$opt->{ch} ? sql('(ASCII(v.title) <', \97, 'OR ASCII(v.title) >', \122, ') AND (ASCII(v.title) <', \65, 'OR ASCII(v.title) >', \90, ')') : ();

    my $count = tuwf->dbVali('SELECT count(*) FROM ulist_vns uv JOIN vn v ON v.id = uv.vid WHERE', $where);

    my $lst = tuwf->dbPagei({ page => $opt->{p}, results => 50 },
        'SELECT v.id, v.title, v.original, uv.vote, uv.notes, uv.started, uv.finished, v.c_rating, v.c_votecount, v.c_released
              ,', sql_totime('uv.added'), ' as added
              ,', sql_totime('uv.lastmod'), ' as lastmod
              ,', sql_totime('uv.vote_date'), ' as vote_date
           FROM ulist_vns uv
           JOIN vn v ON v.id = uv.vid
          WHERE', $where, '
          ORDER BY', {
                    title    => 'v.title',
                    label    => sql('ARRAY(SELECT ul.label FROM ulist_vns_labels uvl JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl WHERE uvl.uid = uv.uid AND uvl.vid = uv.vid AND uvl.lbl <> ', \7, ')'),
                    vote     => 'uv.vote',
                    voted    => 'uv.vote_date',
                    added    => 'uv.added',
                    modified => 'uv.lastmod',
                    started  => 'uv.started',
                    finished => 'uv.finished',
                    rel      => 'v.c_released',
                    rating   => 'v.c_rating',
                }->{$opt->{s}}, $opt->{o} eq 'd' ? 'DESC' : 'ASC', 'NULLS LAST, v.title'
    );

    enrich_flatten labels => id => vid => sql('SELECT vid, lbl FROM ulist_vns_labels WHERE uid =', \$uid, 'AND vid IN'), $lst;

    enrich rels => id => vid => sub { sql '
        SELECT rv.vid, r.id, rl.status
          FROM rlists rl
          JOIN releases r ON rl.rid = r.id
          JOIN releases_vn rv ON rv.id = r.id
         WHERE rl.uid =', \$uid, '
           AND rv.vid IN', $_, '
         ORDER BY r.released, r.title, r.id'
    }, $lst;
    enrich_release_elm map $_->{rels}, @$lst;

    # TODO: Thumbnail view?
    paginate_ $url, $opt->{p}, [ $count, 50 ], 't', sub {
        elm_ ColSelect => 'raw', [ $url->(), [
            [ voted    => 'Vote date'    ],
            [ vote     => 'Vote'         ],
            [ rating   => 'Rating'       ],
            [ label    => 'Labels'       ],
            [ added    => 'Added'        ],
            [ modified => 'Modified'     ],
            [ started  => 'Start date'   ],
            [ finished => 'Finish date'  ],
            [ rel      => 'Release date' ],
        ] ];
    };
    div_ class => 'mainbox browse ulist', sub {
        table_ sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub {
                    input_ type => 'checkbox', class => 'checkall', name => 'collapse_vid', id => 'collapse_vid';
                    label_ for => 'collapse_vid', sub { txt_ 'Opt' };
                };
                td_ class => 'tc_voted',    sub { txt_ 'Vote date';   sortable_ 'voted',    $opt, $url } if in voted    => $opt->{c};
                td_ class => 'tc_vote',     sub { txt_ 'Vote';        sortable_ 'vote',     $opt, $url } if in vote     => $opt->{c};
                td_ class => 'tc_rating',   sub { txt_ 'Rating';      sortable_ 'rating',   $opt, $url } if in rating   => $opt->{c};
                td_ class => 'tc_labels',   sub { txt_ 'Labels';      sortable_ 'label',    $opt, $url } if in label    => $opt->{c};
                td_ class => 'tc_title',    sub { txt_ 'Title';       sortable_ 'title',    $opt, $url; debug_ $lst };
                td_ class => 'tc_added',    sub { txt_ 'Added';       sortable_ 'added',    $opt, $url } if in added    => $opt->{c};
                td_ class => 'tc_modified', sub { txt_ 'Modified';    sortable_ 'modified', $opt, $url } if in modified => $opt->{c};
                td_ class => 'tc_started',  sub { txt_ 'Start date';  sortable_ 'started',  $opt, $url } if in started  => $opt->{c};
                td_ class => 'tc_finished', sub { txt_ 'Finish date'; sortable_ 'finished', $opt, $url } if in finished => $opt->{c};
                td_ class => 'tc_rel',      sub { txt_ 'Release date';sortable_ 'rel',      $opt, $url } if in rel      => $opt->{c};
            }};
            vn_ $uid, $own, $opt, $_, $lst->[$_], $labels for (0..$#$lst);
        };
    };
    paginate_ $url, $opt->{p}, [ $count, 50 ], 'b';
}


# TODO: Ability to add VNs from this page
TUWF::get qr{/$RE{uid}/ulist}, sub {
    my $u = tuwf->dbRowi('SELECT id,', sql_user(), ', ulist_votes, ulist_vnlist, ulist_wish FROM users u WHERE id =', \tuwf->capture('id'));
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
    framework_ title => $title, type => 'u', dbobj => $u, tab => $tab, js => 1,
        $own ? ( pagevars => {
            uid         => $u->{id}*1,
            labels      => $VNWeb::ULists::Elm::LABELS->analyze->{keys}{labels}->coerce_for_json($labels),
            voteprivate => (map \($_->{private}?1:0), grep $_->{id} == 7, @$labels),
        } ) : (),
    sub {
        my $empty = !grep $_->{count}, @$filtlabels;
        div_ class => 'mainbox', sub {
            h1_ $title;
            if($empty) {
                p_ $own
                    ? 'Your list is empty! You can add visual novels to your list from the visual novel pages.'
                    : user_displayname($u).' does not have any visible visual novels in their list.';
            } else {
                filters_ $own, $filtlabels, $opt, $opt_labels, \&url;
                elm_ 'UList.ManageLabels' if $own;
                elm_ 'UList.SaveDefault', $VNWeb::ULists::Elm::SAVED_OPTS_OUT, { uid => $u->{id}, opts => $opt } if $own;
                div_ class => 'hidden exportlist', sub {
                    b_ 'Export your list';
                    br_;
                    txt_ 'This function will export all visual novels and releases in your list, even those marked as private ';
                    txt_ '(there is currently no import function, more export options may be added later).';
                    br_;
                    br_;
                    a_ href => "/u$u->{id}/list-export/xml", "Download XML export.";
                } if $own;
            }
        };
        listing_ $u->{id}, $own, $opt, $labels, \&url if !$empty;
    };
};



# Redirects for old URLs
TUWF::get qr{/$RE{uid}/votes}, sub { tuwf->resRedirect("/u".tuwf->capture('id').'/ulist?votes=1', 'perm') };
TUWF::get qr{/$RE{uid}/list},  sub { tuwf->resRedirect("/u".tuwf->capture('id').'/ulist?vnlist=1', 'perm') };
TUWF::get qr{/$RE{uid}/wish},  sub { tuwf->resRedirect("/u".tuwf->capture('id').'/ulist?wishlist=1', 'perm') };


1;
