package VNWeb::Misc::HomePage;

use VNWeb::Prelude;
use VNWeb::AdvSearch;
use VNWeb::Discussions::Lib 'enrich_boards';


sub screens_ {
    state $where  ||= sql 'i.c_weight > 0 and vndbid_type(i.id) =', \'sf', 'and i.c_sexual_avg <', \40, 'and i.c_violence_avg <', \40;
    state $stats  ||= tuwf->dbRowi('SELECT count(*) as total, count(*) filter(where', $where, ') as subset from images i');
    state $sample ||= 100*min 1, (200 / $stats->{subset}) * ($stats->{total} / $stats->{subset});

    my $filt = advsearch_default 'v';
    my $lst = $filt->{query} ? tuwf->dbAlli(
        # Assumption: If we randomly select 30 matching VNs, there'll be at least 4 VNs with qualified screenshots
        # (As of Sep 2020, over half of the VNs in the database have screenshots, so that assumption usually works)
        'SELECT * FROM (
            SELECT DISTINCT ON (v.id) i.id, i.width, i,height, v.id AS vid, v.title
              FROM (SELECT id, title FROM', vnt, 'v WHERE NOT v.hidden AND ', $filt->sql_where(), ' ORDER BY random() LIMIT', \30, ') v
              JOIN vn_screenshots vs ON v.id = vs.id
              JOIN images i ON i.id = vs.scr
             WHERE ', $where, '
             ORDER BY v.id
        ) x ORDER BY random() LIMIT', \4
    ) : tuwf->dbAlli('
        SELECT i.id, i.width, i.height, v.id AS vid, v.title
          FROM (SELECT id, width, height FROM images i TABLESAMPLE SYSTEM (', \$sample, ') WHERE', $where, ' ORDER BY random() LIMIT', \4, ') i(id)
          JOIN vn_screenshots vs ON vs.scr = i.id
          JOIN', vnt, 'v ON v.id = vs.id
         WHERE NOT v.hidden
         ORDER BY random()
         LIMIT', \4
    );

    p_ class => 'screenshots', sub {
        a_ href => "/$_->{vid}", title => $_->{title}[1], sub {
            my($w, $h) = imgsize $_->{width}, $_->{height}, config->{scr_size}->@*;
            img_ src => imgurl($_->{id}, 1), alt => $_->{title}[1], width => $w, height => $h;
        } for @$lst;
    }
}


sub recent_changes_ {
    my($lst) = VNWeb::Misc::History::fetch(undef, {m=>1,h=>1,p=>1}, {results=>10});
    h1_ sub {
        a_ href => '/hist', 'Recent Changes'; txt_ ' ';
        a_ href => '/feeds/changes.atom', sub {
            abbr_ class => 'icon-rss', title => 'Atom feed', '';
        }
    };
    ul_ sub {
        li_ sub {
            span_ sub {
                txt_ "$1:" if $_->{itemid} =~ /^(.)/;
                a_ href => "/$_->{itemid}.$_->{rev}", tattr $_;
            };
            span_ sub {
                lit_ " by ";
                user_ $_;
            }
        } for @$lst;
    };
}


sub recent_db_posts_ {
    my $an = tuwf->dbAlli('
        SELECT t.id, t.title,', sql_totime('tp.date'), 'AS date
          FROM threads t
          JOIN threads_boards tb ON tb.tid = t.id AND tb.type = \'an\'
          JOIN threads_posts tp ON tp.tid = t.id AND tp.num = 1
         WHERE NOT t.hidden AND NOT t.private AND tp.date >', sql_fromtime(time-30*24*3600), '
         ORDER BY tb.tid DESC
         LIMIT 1+1'
    );
    my $lst = tuwf->dbAlli('
        SELECT t.id, t.title, tp.num,', sql_totime('tp.date'), 'AS date, ', sql_user(), '
          FROM threads t
          JOIN threads_posts tp ON tp.tid = t.id AND tp.num = t.c_lastnum
          LEFT JOIN users u ON tp.uid = u.id
         WHERE EXISTS(SELECT 1 FROM threads_boards tb WHERE tb.tid = t.id AND tb.type IN(\'db\',\'an\'))
           AND NOT t.hidden AND NOT t.private
         ORDER BY tp.date DESC
         LIMIT', \(10-@$an)
    );
    enrich_boards undef, $lst;
    p_ class => 'mainopts', sub {
        a_ href => '/t/an', 'Announcements';
        small_ '&';
        a_ href => '/t/db', 'VNDB';
    };
    h1_ sub {
        txt_ 'DB Discussions';
    };
    ul_ sub {
        li_ class => 'announcement', sub {
            a_ href => "/$_->{id}", $_->{title};
        } for @$an;
        li_ sub {
            my $boards = join ', ', map $BOARD_TYPE{$_->{btype}}{txt}.($_->{iid}?' > '.$_->{title}[1]:''), $_->{boards}->@*;
            span_ sub {
                txt_ fmtage($_->{date}).' ';
                a_ href => "/$_->{id}.$_->{num}#last", title => "Posted in $boards", $_->{title};
            };
            span_ sub {
                lit_ ' by ';
                user_ $_;
            }
        } for @$lst;
    };
}


sub recent_vn_posts_ {
    my $lst = tuwf->dbAlli('
        WITH tposts (id,title,num,date,uid) AS (
            SELECT t.id, ARRAY[NULL, t.title], tp.num, tp.date, tp.uid
              FROM threads t
              JOIN threads_posts tp ON tp.tid = t.id AND tp.num = t.c_lastnum
             WHERE NOT EXISTS(SELECT 1 FROM threads_boards tb WHERE tb.tid = t.id AND tb.type IN(\'an\',\'db\',\'u\'))
               AND NOT t.hidden AND NOT t.private
             ORDER BY tp.date DESC LIMIT 10
        ), wposts (id,title,num,date,uid) AS (
            SELECT w.id, v.title, wp.num, wp.date, wp.uid
              FROM reviews w
              JOIN reviews_posts wp ON wp.id = w.id AND wp.num = w.c_lastnum
              JOIN', vnt, 'v ON v.id = w.vid
              LEFT JOIN users u ON wp.uid = u.id
             WHERE NOT w.c_flagged AND wp.hidden IS NULL
             ORDER BY wp.date DESC LIMIT 10
        ) SELECT x.id, x.num, x.title,', sql_totime('x.date'), 'AS date, ', sql_user(), '
            FROM (SELECT * FROM tposts UNION ALL SELECT * FROM wposts) x
            LEFT JOIN users u ON u.id = x.uid
           ORDER BY date DESC
           LIMIT 10'
    );
    enrich_boards undef, $lst;
    p_ class => 'mainopts', sub {
        a_ href => '/t/all', 'Forums';
        small_ '&';
        a_ href => '/w?o=d&s=lastpost', 'Reviews';
    };
    h1_ sub {
        a_ href => '/t/all', 'VN Discussions';
    };
    ul_ sub {
        li_ sub {
            span_ sub {
                my $boards = join ', ', map $BOARD_TYPE{$_->{btype}}{txt}.($_->{iid}?' > '.$_->{title}[1]:''), $_->{boards}->@*;
                txt_ fmtage($_->{date}).' ';
                a_ href => "/$_->{id}.$_->{num}#last", title => $boards ? "Posted in $boards" : 'Review', tlang(@{$_->{title}}[0,1]), $_->{title}[1];
            };
            span_ sub {
                lit_ ' by ';
                user_ $_;
            }
        } for @$lst;
    };
}



sub releases_ {
    my($released) = @_;

    my $filt = advsearch_default 'r';

    # Drop any top-level date filters
    $filt->{query} = [ grep !(ref $_ eq 'ARRAY' && $_->[0] eq 'released'), $filt->{query}->@* ] if $filt->{query};
    delete $filt->{query} if $filt->{query} && ($filt->{query}[0] eq 'released' || $filt->{query}->@* < 2);

    # Add the release date as filter, we need to construct a filter for the header link anyway
    $filt->{query} = [ 'and', [ released => $released ? '<=' : '>', 1 ], $filt->{query} || () ];

    my $lst = tuwf->dbAlli('
        SELECT id, title, released
          FROM', releasest, 'r
         WHERE NOT hidden AND ', $filt->sql_where(), '
           AND NOT EXISTS(SELECT 1 FROM releases_titles rt WHERE rt.id = r.id AND rt.mtl)
         ORDER BY released', $released ? 'DESC' : '', ', id LIMIT 10'
    );
    enrich_flatten plat => id => id => 'SELECT id, platform FROM releases_platforms WHERE id IN', $lst;
    enrich_flatten lang => id => id => 'SELECT id, lang     FROM releases_titles    WHERE id IN', $lst;

    h1_ sub {
        a_ href => '/r?f='.$filt->query_encode().';o=a;s=released', 'Upcoming Releases' if !$released;
        a_ href => '/r?f='.$filt->query_encode().';o=d;s=released', 'Just Released' if $released;
    };
    ul_ sub {
        li_ sub {
            span_ sub {
                rdate_ $_->{released};
                txt_ ' ';
                platform_ $_ for $_->{plat}->@*;
                abbr_ class => "icon-lang-$_", title => $LANGUAGE{$_}{txt}, '' for $_->{lang}->@*;
                txt_ ' ';
                a_ href => "/$_->{id}", tattr $_;
            }
        } for @$lst;
    };
}


sub reviews_ {
    my $lst = tuwf->dbAlli('
        SELECT w.id, v.title, w.isfull, ', sql_user(), ',', sql_totime('w.date'), 'AS date
          FROM reviews w
          JOIN', vnt, 'v ON v.id = w.vid
          LEFT JOIN users u ON u.id = w.uid
         WHERE NOT w.c_flagged
         ORDER BY w.id DESC LIMIT 10'
    );
    h1_ sub {
        a_ href => '/w', 'Latest Reviews';
    };
    ul_ sub {
        li_ sub {
            span_ sub {
                txt_ fmtage($_->{date}).' ';
                small_ $_->{isfull} ? ' Full ' : ' Mini ';
                a_ href => "/$_->{id}", tattr $_;
            };
            span_ sub {
                lit_ 'by ';
                user_ $_;
            }
        } for @$lst;
    }
}


TUWF::get qr{/}, sub {
    my %meta = (
        'type' => 'website',
        'title' => 'The Visual Novel Database',
        'description' => 'VNDB.org strives to be a comprehensive database for information about visual novels.',
    );

    framework_ title => $meta{title}, feeds => 1, og => \%meta, index => 1, sub {
        article_ sub {
            h1_ $meta{title};
            p_ class => 'description', sub {
                txt_ $meta{description};
                br_;
                txt_ q{
                  This website is built as a wiki, meaning that anyone can freely add
                  and contribute information to the database, allowing us to create the
                  largest, most accurate and most up-to-date visual novel database on the web.
                };
            };
            screens_;
        };
        div_ class => 'homepage', sub {
            article_ \&recent_changes_;
            article_ \&recent_db_posts_;
            article_ \&recent_vn_posts_;
            article_ sub { reviews_ };
            article_ sub { releases_ 0 };
            article_ sub { releases_ 1 };
        };
    };
};

1;
