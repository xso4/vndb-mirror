package VNWeb::ULists::Main;

use VNWeb::Prelude;
use VNWeb::ULists::Lib;
use VNWeb::Releases::Lib;


my $TABLEOPTS = VNWeb::VN::List::TABLEOPTS('ulist');


sub opt {
    my($u, $labels) = @_;

    # Note that saved defaults may still use the old query format, which is
    #   { s => $sort_column, o => $order, c => [$visible_columns] }
    my sub load { my $o = $u->{"ulist_$_[0]"}; ($o && eval { JSON::XS->new->decode($o) } or {})->%* };

    state $s_default  = tuwf->compile({ tableopts => $TABLEOPTS })->validate(undef)->data;
    state $s_vnlist   = $s_default->sort_param(title => 'a')->vis_param(qw/label vote added started finished/)->query_encode;
    state $s_votes    = $s_default->sort_param(voted => 'd')->vis_param(qw/vote voted/)->query_encode;
    state $s_wishlist = $s_default->sort_param(title => 'a')->vis_param(qw/label added/)->query_encode;
    state @all = (mul => 0, p => 1, f => '', q => tuwf->compile({ searchquery => 1 })->validate(undef)->data);

    my $opt =
        # Presets
        tuwf->reqGet('vnlist')   ? { @all, l => [1,2,3,4,7,0], s => $s_vnlist,   load 'vnlist' } :
        tuwf->reqGet('votes')    ? { @all, l => [7],           s => $s_votes,    load 'votes'  } :
        tuwf->reqGet('wishlist') ? { @all, l => [5],           s => $s_wishlist, load 'wish'   } :
        # Full options
        tuwf->validate(get =>
            p => { upage => 1 },
            ch=> { onerror => [], type => 'array', scalar => 1, values => { onerror => undef, enum => ['0', 'a'..'z'] } },
            q => { searchquery => 1 },
            %VNWeb::ULists::Elm::SAVED_OPTS,
            # Compat for old URLs
            o => { onerror => undef, enum => ['a', 'd'] },
            c => { onerror => undef, type => 'array', scalar => 1, values => { enum => [qw[ label vote voted added modified started finished rel rating ]] } },
        )->data;
    $opt->{ch} = $opt->{ch}[0];

    $opt->{s} .= "/$opt->{o}" if $opt->{o};
    $opt->{s} = tuwf->compile({ tableopts => $TABLEOPTS })->validate($opt->{s})->data;
    $opt->{s} = $opt->{s}->vis_param($opt->{c}->@*) if $opt->{c};
    delete $opt->{o};
    delete $opt->{c};

    $opt->{f} = tuwf->compile({ advsearch_err => 'v' })->validate($opt->{f})->data;

    # $labels only includes labels we are allowed to see, getting rid of any
    # labels in 'l' that aren't in $labels ensures we only filter on visible
    # labels.
    # Also, '-1' used to refer to the virtual "No label" label, now it's '0' instead.
    my %accessible_labels = map +($_->{id}, 1), @$labels;
    my %opt_l = map +($_, 1), grep $accessible_labels{$_}, map $_ == -1 ? 0 : $_, $opt->{l}->@*;
    %opt_l = %accessible_labels if !keys %opt_l;
    $opt->{l} = keys %opt_l == keys %accessible_labels ? [] : [ sort keys %opt_l ];

    ($opt, \%opt_l)
}


sub filters_ {
    my($own, $labels, $opt, $opt_labels, $url) = @_;

    my sub lblfilt_ {
        input_ type => 'checkbox', name => 'l', value => $_->{id}, id => "form_l$_->{id}", tabindex => 10, $opt_labels->{$_->{id}} ? (checked => 'checked') : ();
        label_ for => "form_l$_->{id}", "$_->{label} ";
        txt_ " ($_->{count})";
    }

    div_ class => 'labelfilters', sub {
        # Implicit behavior alert: pressing enter in this input will activate
        # the *first* submit button in the form, which happens to be the "ALL"
        # character selector. Let's just pretend that is intended behavior.
        input_ type => 'text', class => 'text', name => 'q', value => $opt->{q}||'', style => 'width: 500px', placeholder => 'Search', tabindex => 10;
        br_;
        span_ class => 'browseopts', sub {
            button_ type => 'submit', name => 'ch', value => ($_//''), ($_//'') eq ($opt->{ch}//'') ? (class => 'optselected') : (), !defined $_ ? 'ALL' : $_ ? uc $_ : '#'
                for (undef, 'a'..'z', 0);
        };
        input_ type => 'hidden', name => 'ch', value => $opt->{ch}//'';
        $opt->{f}->elm_;
        p_ class => 'linkradio', sub {
            join_ sub { em_ ' / ' }, \&lblfilt_, grep $_->{id} < 10, @$labels;
            span_ class => 'hidden', sub {
                em_ ' || ';
                input_ type => 'checkbox', name => 'mul', value => 1, id => 'form_l_multi', tabindex => 10, $opt->{mul} ? (checked => 'checked') : ();
                label_ for => 'form_l_multi', 'Multi-select';
            };
            debug_ $labels;
            my @cust = grep $_->{id} >= 10, @$labels;
            if(@cust) {
                br_;
                join_ sub { em_ ' / ' }, \&lblfilt_, @cust;
            }
        };
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
                span_ id => 'ulist_relsum_'.$v->{id},
                    mkclass(done => $total && $obtained == $total, todo => $obtained < $total),
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

        td_ class => 'tc_pop',   sprintf '%.2f', ($v->{c_popularity}||0)/100 if $opt->{s}->vis('popularity');
        td_ class => 'tc_rating', sub {
            txt_ sprintf '%.2f', ($v->{c_rating}||0)/100;
            small_ sprintf ' (%d)', $v->{c_votecount};
        } if $opt->{s}->vis('rating');
        td_ class => 'tc_average',sub {
            txt_ sprintf '%.2f', ($v->{c_average}||0)/100;
            small_ sprintf ' (%d)', $v->{c_votecount} if !$opt->{s}->vis('rating');
        } if $opt->{s}->vis('average');

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
            a_ href => "/$v->{id}", tattr $v;
            small_ id => 'ulist_notes_'.$v->{id}, $v->{notes} if $v->{notes} || $own;
        };
        td_ class => 'tc_dev',   sub {
            join_ ' & ', sub {
                a_ href => "/$_->{id}", tattr $_;
            }, $v->{developers}->@*;
        } if $opt->{s}->vis('developer');

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

        td_ class => 'tc_rel', sub { rdate_ $v->{c_released} } if $opt->{s}->vis('released');
        td_ class => 'tc_length',sub { VNWeb::VN::List::len_($v) } if $opt->{s}->vis('length');
    };

    tr_ mkclass(hidden => 1, 'collapsed_vid'.$v->{id} => 1, odd => $n % 2 == 0), sub {
        td_ colspan => 7, class => 'tc_opt', sub {
            my $relstatus = [ map $_->{status}, $v->{rels}->@* ];
            elm_ 'UList.Opt' => $VNWeb::ULists::Elm::VNOPT, { own => $own?1:0, uid => $uid, vid => $v->{id}, notes => $v->{notes}, rels => $v->{rels}, relstatus => $relstatus };
        };
    };
}


sub listing_ {
    my($uid, $own, $opt, $labels, $url) = @_;

    my @l = grep $_ > 0 && $_ != 7, $opt->{l}->@*;
    my $unlabeled = grep $_ == 0, $opt->{l}->@*;
    my $voted = grep $_ == 7, $opt->{l}->@*;

    my @where_vns = (
              @l ? sql('uv.labels &&', sql_array(@l), '::smallint[]') : (),
      $unlabeled ? sql("uv.labels IN('{}','{7}')") : (),
          $voted ? sql('uv.vote IS NOT NULL') : ()
    );

    my $where = sql_and
        sql('uv.uid =', \$uid),
        $opt->{f}->sql_where(),
        $opt->{q}->sql_where('v', 'v.id'),
        $own ? () : 'NOT uv.c_private AND NOT v.hidden',
        @where_vns ? sql_or(@where_vns) : (),
        defined($opt->{ch}) ? sql 'match_firstchar(v.sorttitle, ', \$opt->{ch}, ')' : ();

    my $count = tuwf->dbVali('SELECT count(*) FROM ulist_vns uv JOIN', vnt, 'v ON v.id = uv.vid WHERE', $where);

    my $lst = tuwf->dbPagei({ page => $opt->{p}, results => $opt->{s}->results },
        'SELECT v.id, v.title, uv.vote, uv.notes, uv.labels, uv.started, uv.finished
              , v.c_released, v.c_popularity, v.c_average, v.c_rating, v.c_votecount, v.c_released
              , v.image, v.c_platforms::text[] AS platforms, v.c_languages::text[] AS lang
              ,', sql_totime('uv.added'), ' as added
              ,', sql_totime('uv.lastmod'), ' as lastmod
              ,', sql_totime('uv.vote_date'), ' as vote_date',
                 $opt->{s}->vis('length') ? ', v.length, v.c_length, v.c_lengthnum' : (), '
           FROM ulist_vns uv
           JOIN', vnt, 'v ON v.id = uv.vid
          WHERE', $where, '
          ORDER BY', $opt->{s}->sql_order(), 'NULLS LAST, v.sorttitle'
    );

    enrich rels => id => vid => sub { sql '
        SELECT rv.vid, r.id, rl.status, rv.rtype
          FROM rlists rl
          JOIN', releasest, 'r ON rl.rid = r.id
          JOIN releases_vn rv ON rv.id = r.id
         WHERE rl.uid =', \$uid, '
           AND rv.vid IN', $_, '
         ORDER BY r.released, r.sorttitle, r.id'
    }, $lst;
    enrich_release_elm map $_->{rels}, @$lst;
    VNWeb::VN::List::enrich_listing(auth && auth->uid eq $uid && !$opt->{s}->rows(), $opt, $lst);

    return VNWeb::VN::List::listing_($opt, $lst, $count, 0, $labels) if !$opt->{s}->rows;

    # TODO: Consolidate the 'rows' listing with VN::List as well
    paginate_ $url, $opt->{p}, [$count, $opt->{s}->results], 't', $opt->{s};
    article_ class => 'browse ulist', sub {
        table_ sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub {
                    input_ type => 'checkbox', class => 'checkall', 'x-checkall' => 'collapse_vid', id => 'collapse_vid';
                    label_ for => 'collapse_vid', sub { txt_ 'Opt' };
                };
                td_ class => 'tc_voted',    sub { txt_ 'Vote date';   sortable_ 'voted',    $opt, $url } if $opt->{s}->vis('voted');
                td_ class => 'tc_vote',     sub { txt_ 'Vote';        sortable_ 'vote',     $opt, $url } if $opt->{s}->vis('vote');
                td_ class => 'tc_pop',      sub { txt_ 'Popularity';  sortable_ 'popularity', $opt, $url } if $opt->{s}->vis('popularity');
                td_ class => 'tc_rating',   sub { txt_ 'Rating';      sortable_ 'rating',   $opt, $url } if $opt->{s}->vis('rating');
                td_ class => 'tc_average',  sub { txt_ 'Average';     sortable_ 'average',    $opt, $url } if $opt->{s}->vis('average');
                td_ class => 'tc_labels',   sub { txt_ 'Labels';      sortable_ 'label',    $opt, $url } if $opt->{s}->vis('label');
                td_ class => 'tc_title',    sub { txt_ 'Title';       sortable_ 'title',    $opt, $url; debug_ $lst };
                td_ class => 'tc_dev',      'Developer' if $opt->{s}->vis('developer');
                td_ class => 'tc_added',    sub { txt_ 'Added';       sortable_ 'added',    $opt, $url } if $opt->{s}->vis('added');
                td_ class => 'tc_modified', sub { txt_ 'Modified';    sortable_ 'modified', $opt, $url } if $opt->{s}->vis('modified');
                td_ class => 'tc_started',  sub { txt_ 'Start date';  sortable_ 'started',  $opt, $url } if $opt->{s}->vis('started');
                td_ class => 'tc_finished', sub { txt_ 'Finish date'; sortable_ 'finished', $opt, $url } if $opt->{s}->vis('finished');
                td_ class => 'tc_rel',      sub { txt_ 'Release date';sortable_ 'released', $opt, $url } if $opt->{s}->vis('released');
                td_ class => 'tc_length',   'Length' if $opt->{s}->vis('length');
            }};
            vn_ $uid, $own, $opt, $_, $lst->[$_], $labels for (0..$#$lst);
        };
    };
    paginate_ $url, $opt->{p}, [$count, $opt->{s}->results], 'b';
}


TUWF::get qr{/$RE{uid}/ulist}, sub {
    my $u = tuwf->dbRowi('
        SELECT u.id,', sql_user(), ', ulist_votes, ulist_vnlist, ulist_wish
          FROM users u JOIN users_prefs up ON up.id = u.id
         WHERE u.id =', \tuwf->capture('id'));
    return tuwf->resNotFound if !$u->{id};

    my $own = ulists_own $u->{id};
    my $labels = ulist_filtlabels $u->{id}, 1;
    $_->{delete} = undef for @$labels;

    my($opt, $opt_labels) = opt $u, $labels;
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
        my $empty = !grep $_->{count}, @$labels;
        form_ method => 'get', sub {
            article_ sub {
                h1_ $title;
                if($empty) {
                    p_ $own
                        ? 'Your list is empty! You can add visual novels to your list from the visual novel pages.'
                        : user_displayname($u).' does not have any visible visual novels in their list.';
                } else {
                    filters_ $own, $labels, $opt, $opt_labels, \&url;
                    elm_ 'UList.ManageLabels' if $own;
                    elm_ 'UList.SaveDefault', $VNWeb::ULists::Elm::SAVED_OPTS_OUT, {
                        uid => $u->{id},
                        opts => { l => $opt->{l}, mul => $opt->{mul}, s => $opt->{s}->query_encode(), f => $opt->{f}->query_encode() },
                    } if $own;
                    div_ class => 'hidden exportlist', sub {
                        strong_ 'Export your list';
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
