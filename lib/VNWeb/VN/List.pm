package VNWeb::VN::List;

use VNWeb::Prelude;
use VNWeb::AdvSearch;
use VNWeb::Filters;
use VNWeb::TT::Lib 'tagscore_';


# Also used by VNWeb::TT::TagPage
sub listing_ {
    my($opt, $list, $count, $tagscore) = @_;

    my sub url { '?'.query_encode %$opt, @_ }

    paginate_ \&url, $opt->{p}, [$count, 50], 't';
    div_ class => 'mainbox browse vnbrowse', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc_s',sub { txt_ 'Score'; sortable_ 'tagscore', $opt, \&url } if $tagscore;
                td_ class => $tagscore ? 'tc_t' : 'tc1', sub { txt_ 'Title'; sortable_ 'title', $opt, \&url };
                td_ class => 'tc7', '';
                td_ class => 'tc2', '';
                td_ class => 'tc3', '';
                td_ class => 'tc4', sub { txt_ 'Released';   sortable_ 'rel',    $opt, \&url };
                td_ class => 'tc5', sub { txt_ 'Popularity'; sortable_ 'pop',    $opt, \&url };
                td_ class => 'tc6', sub { txt_ 'Rating';     sortable_ 'rating', $opt, \&url };
            } };
            tr_ sub {
                td_ class => 'tc_s',sub { tagscore_ $_->{tagscore} } if $tagscore;
                td_ class => $tagscore ? 'tc_t' : 'tc1', sub { a_ href => "/$_->{id}", title => $_->{original}||$_->{title}, $_->{title} };
                td_ class => 'tc7', sub {
                    b_ class => $_->{userlist_obtained} == $_->{userlist_all} ? 'done' : 'todo', sprintf '%d/%d', $_->{userlist_obtained}, $_->{userlist_all} if $_->{userlist_all};
                    abbr_ title => join(', ', $_->{vnlist_labels}->@*), scalar $_->{vnlist_labels}->@* if $_->{vnlist_labels} && $_->{vnlist_labels}->@*;
                    abbr_ title => 'No labels', ' ' if $_->{vnlist_labels} && !$_->{vnlist_labels}->@*;
                };
                td_ class => 'tc2', sub { join_ '', sub { platform_ $_ if $_ ne 'unk' }, sort $_->{platforms}->@* };
                td_ class => 'tc3', sub { join_ '', sub { abbr_ class => "icons lang $_", title => $LANGUAGE{$_}, '' }, reverse sort $_->{lang}->@* };
                td_ class => 'tc4', sub { rdate_ $_->{c_released} };
                td_ class => 'tc5', sprintf '%.2f', ($_->{c_popularity}||0)*100;
                td_ class => 'tc6', sub {
                    txt_ sprintf '%.2f', ($_->{c_rating}||0)/10;
                    b_ class => 'grayedout', sprintf ' (%d)', $_->{c_votecount};
                };
            } for @$list;
        }
    };
    paginate_ \&url, $opt->{p}, [$count, 50], 'b';
}


# Enrich the userlist fields needed for listing_()
# Also used by VNWeb::TT::TagPage
sub enrich_userlist {
    return if !auth;

    enrich_merge id => sub { sql '
        SELECT irv.vid AS id
             , COUNT(*) AS userlist_all
             , SUM(CASE WHEN irl.status = 1+1 THEN 1 ELSE 0 END) AS userlist_obtained
         FROM rlists irl
         JOIN releases_vn irv ON irv.id = irl.rid
        WHERE irl.uid =', \auth->uid, 'AND irv.vid IN', $_, '
        GROUP BY irv.vid
    ' }, @_;

    enrich_flatten vnlist_labels => id => vid => sub { sql '
        SELECT uvl.vid, ul.label
          FROM ulist_vns_labels uvl
          JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl
         WHERE uvl.uid =', \auth->uid, 'AND uvl.vid IN', $_[0], '
         ORDER BY CASE WHEN ul.id < 10 THEN ul.id ELSE 10 END, ul.label'
    }, @_;
}


TUWF::get qr{/v(?:/(?<char>all|[a-z0]))?}, sub {
    my $opt = tuwf->validate(get =>
        q => { onerror => undef },
        sq=> { onerror => undef },
        p => { upage => 1 },
        f => { advsearch_err => 'v' },
        s => { onerror => 'title', enum => [qw/title rel pop rating/] },
        o => { onerror => 'a', enum => ['a','d'] },
        ch=> { onerror => [], type => 'array', scalar => 1, values => { onerror => undef, enum => ['0', 'a'..'z'] } },
        fil  => { required => 0 },
        rfil => { required => 0 },
        cfil => { required => 0 },
    )->data;
    $opt->{q} //= $opt->{sq};
    $opt->{ch} = $opt->{ch}[0];

    # compat with old URLs
    my $oldch = tuwf->capture('char');
    $opt->{ch} //= $oldch if defined $oldch && $oldch ne 'all';

    # URL compatibility with old filters
    if(!$opt->{f}->{query} && ($opt->{fil} || $opt->{rfil} || $opt->{cfil})) {
        my $q = eval {
            my $fil  = filter_vn_adv      filter_parse v => $opt->{fil};
            my $rfil = filter_release_adv filter_parse r => $opt->{rfil};
            my $cfil = filter_char_adv    filter_parse c => $opt->{cfil};
            my @q = (
                $fil && @$fil > 1 ? $fil : (),
                $rfil && @$rfil > 1 ? [ 'release', '=', $rfil ] : (),
                $cfil && @$cfil > 1 ? [ 'character', '=', $cfil ] : (),
            );
            tuwf->compile({ advsearch => 'v' })->validate(@q > 1 ? ['and',@q] : @q)->data;
        };
        return tuwf->resRedirect(tuwf->reqPath().'?'.query_encode(%$opt, fil => undef, rfil => undef, cfil => undef, f => $q), 'perm') if $q;
    }

    $opt->{f} = advsearch_default 'v' if !$opt->{f}{query} && !defined tuwf->reqGet('f');

    my $where = sql_and
        'NOT v.hidden', $opt->{f}->sql_where(),
        $opt->{q} ? map sql('v.c_search LIKE', \"%$_%"), normalize_query $opt->{q} : (),
        defined($opt->{ch}) && $opt->{ch} ? sql('LOWER(SUBSTR(v.title, 1, 1)) =', \$opt->{ch}) : (),
        defined($opt->{ch}) && !$opt->{ch} ? sql('(ASCII(v.title) <', \97, 'OR ASCII(v.title) >', \122, ') AND (ASCII(v.title) <', \65, 'OR ASCII(v.title) >', \90, ')') : ();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = tuwf->dbVali('SELECT count(*) FROM vn v WHERE', $where);
        $list = $count ? tuwf->dbPagei({results => 50, page => $opt->{p}}, '
            SELECT v.id, v.title, v.original, v.c_released, v.c_popularity, v.c_votecount, v.c_rating, v.c_platforms::text[] AS platforms, v.c_languages::text[] AS lang
              FROM vn v
             WHERE', $where, '
             ORDER BY', sprintf {
                 title  => 'v.title %s',
                 rel    => 'v.c_released %s, v.title',
                 pop    => 'v.c_popularity %s NULLS LAST, v.title',
                 rating => 'v.c_rating %s NULLS LAST, v.title'
             }->{$opt->{s}}, $opt->{o} eq 'a' ? 'ASC' : 'DESC'
        ) : [];
    } || (($count, $list) = (undef, []));

    return tuwf->resRedirect("/$list->[0]{id}") if $count && $count == 1 && $opt->{q} && !defined $opt->{ch};

    enrich_userlist $list;
    $time = time - $time;

    framework_ title => 'Browse visual novels', sub {
        div_ class => 'mainbox', sub {
            h1_ 'Browse visual novels';
            form_ action => '/v', method => 'get', sub {
                searchbox_ v => $opt->{q}//'';
                p_ class => 'browseopts', sub {
                    button_ type => 'submit', name => 'ch', value => ($_//''), ($_//'') eq ($opt->{ch}//'') ? (class => 'optselected') : (), !defined $_ ? 'ALL' : $_ ? uc $_ : '#'
                        for (undef, 'a'..'z', 0);
                };
                input_ type => 'hidden', name => 'o', value => $opt->{o};
                input_ type => 'hidden', name => 's', value => $opt->{s};
                input_ type => 'hidden', name => 'ch', value => $opt->{ch}//'';
                $opt->{f}->elm_;
                advsearch_msg_ $count, $time;
            };
        };
        listing_ $opt, $list, $count if $count;
    };
};

1;
