package VNWeb::VN::List;

use VNWeb::Prelude;
use VNWeb::AdvSearch;


sub listing_ {
    my($opt, $list, $count) = @_;

    my sub url { '?'.query_encode %$opt, @_ }

    paginate_ \&url, $opt->{p}, [$count, 50], 't';
    div_ class => 'mainbox browse vnbrowse', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub { txt_ 'Title';      sortable_ 'title',  $opt, \&url };
                td_ class => 'tc7', '';
                td_ class => 'tc2', '';
                td_ class => 'tc3', '';
                td_ class => 'tc4', sub { txt_ 'Released';   sortable_ 'rel',    $opt, \&url };
                td_ class => 'tc5', sub { txt_ 'Popularity'; sortable_ 'pop',    $opt, \&url };
                td_ class => 'tc6', sub { txt_ 'Rating';     sortable_ 'rating', $opt, \&url };
            } };
            tr_ sub {
                td_ class => 'tc1', sub { a_ href => "/v$_->{id}", title => $_->{original}||$_->{title}, $_->{title} };
                td_ class => 'tc7', sub {
                    b_ class => $_->{userlist_obtained} == $_->{userlist_all} ? 'done' : 'todo', sprintf '%d/%d', $_->{userlist_obtained}, $_->{userlist_all} if $_->{userlist_all};
                    abbr_ title => join(', ', $_->{vnlist_labels}->@*), scalar $_->{vnlist_labels}->@* if $_->{vnlist_labels} && $_->{vnlist_labels}->@*;
                    abbr_ title => 'No labels', ' ' if $_->{vnlist_labels} && !$_->{vnlist_labels}->@*;
                };
                td_ class => 'tc2', sub { join_ '', sub { abbr_ class => "icons $_", title => $PLATFORM{$_}, '' if $_ ne 'unk' }, sort $_->{platforms}->@* };
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


TUWF::get qr{/experimental/v}, sub {
    my $opt = tuwf->validate(get =>
        q => { onerror => '' },
        p => { upage => 1 },
        f => { advsearch => 'v' },
        s => { onerror => 'title', enum => [qw/title rel pop rating/] },
        o => { onerror => 'a', enum => ['a','d'] },
    )->data;

    my $where = sql_and
        'NOT v.hidden', $opt->{f}->sql_where(),
        $opt->{q} ? map sql('v.c_search LIKE', \"%$_%"), normalize_query $opt->{q} : ();

    my $time = time;
    my $count = tuwf->dbVali('SELECT count(*) FROM vn v WHERE', $where);
    my $list = $count && tuwf->dbPagei({results => 50, page => $opt->{p}}, '
        SELECT v.id, v.title, v.original, v.c_released, v.c_popularity, v.c_votecount, v.c_rating, v.c_platforms::text[] AS platforms, v.c_languages::text[] AS lang
             , vl.userlist_all, vl.userlist_obtained
          FROM vn v
          LEFT JOIN (
                 SELECT irv.vid, COUNT(*) AS userlist_all
                      , SUM(CASE WHEN irl.status = 1+1 THEN 1 ELSE 0 END) AS userlist_obtained
                   FROM rlists irl
                   JOIN releases_vn irv ON irv.id = irl.rid
                  WHERE irl.uid =', \auth->uid, '
                  GROUP BY irv.vid
               ) AS vl ON vl.vid = v.id
         WHERE', $where, '
         ORDER BY', sprintf {
             title  => 'v.title %s',
             rel    => 'v.c_released %s, v.title',
             pop    => 'v.c_popularity %s NULLS LAST, v.title',
             rating => 'v.c_rating %s NULLS LAST, v.title'
         }->{$opt->{s}}, $opt->{o} eq 'a' ? 'ASC' : 'DESC'
    );
    enrich_flatten vnlist_labels => id => vid => sub { sql '
        SELECT uvl.vid, ul.label
          FROM ulist_vns_labels uvl
          JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl
         WHERE uvl.uid =', \auth->uid, 'AND uvl.vid IN', $_[0], '
         ORDER BY CASE WHEN ul.id < 10 THEN ul.id ELSE 10 END, ul.label'
    }, $list if $count && auth;
    $time = time - $time;

    framework_ title => 'Browse visual novels', sub {
        div_ class => 'mainbox', sub {
            h1_ 'Browse visual novels';
            div_ class => 'warning', sub {
                h2_ 'EXPERIMENTAL';
                p_ "This is Yorhel's playground. Lots of functionality is missing, lots of stuff is or will be broken. Here be dragons. Etc.";
            };
            br_;
            form_ action => '/experimental/v', method => 'get', sub {
                searchbox_ v => $opt->{q};
                $opt->{f}->elm_;
            };
            p_ class => 'center', sprintf '%d results in %.3fs', $count, $time;
        };
        listing_ $opt, $list, $count if $count;
    };
};

1;
