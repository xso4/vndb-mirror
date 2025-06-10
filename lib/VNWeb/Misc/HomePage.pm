package VNWeb::Misc::HomePage;

use VNWeb::Prelude;
use VNWeb::AdvSearch;
use VNWeb::Discussions::Lib 'enrich_boards';


sub screens {
    state $where  = "i.c_weight > 0 AND vndbid_type(i.id) = 'sf' AND i.c_sexual_avg < 40 AND i.c_violence_avg < 40";
    state $stats  = fu->sql("SELECT count(*) as total, count(*) filter(where $where) as subset from images i")->cache(0)->rowh;
    state $sample ||= 100*min 1, (200 / (1+$stats->{subset})) * ($stats->{total} / (1+$stats->{subset}));

    my $filt = advsearch_default 'v';
    my $start = time;
    my $lst = $filt->{query} ? fu->SQL(
        # Assumption: If we randomly select 30 matching VNs, there'll be at least 4 VNs with qualified screenshots
        # (As of Sep 2020, over half of the VNs in the database have screenshots, so that assumption usually works)
        'SELECT * FROM (
            SELECT DISTINCT ON (v.id) i.id, i.width, i,height, v.id AS vid, v.title
              FROM (SELECT id, title FROM', VNT, 'v WHERE NOT v.hidden AND ', $filt->WHERE, ' ORDER BY random() LIMIT 30) v
              JOIN vn_screenshots vs ON v.id = vs.id
              JOIN images i ON i.id = vs.scr
             WHERE ', RAW($where), '
             ORDER BY v.id
        ) x ORDER BY random() LIMIT 4'
    )->allh : fu->SQL('
        SELECT i.id, i.width, i.height, v.id AS vid, v.title
          FROM (SELECT id, width, height FROM images i TABLESAMPLE SYSTEM (', $sample, ') WHERE', RAW($where), ' ORDER BY random() LIMIT 4) i(id)
          JOIN vn_screenshots vs ON vs.scr = i.id
          JOIN', VNT, 'v ON v.id = vs.id
         WHERE NOT v.hidden
         ORDER BY random()
         LIMIT 4'
    )->allh;
    ($lst, $filt->{query} && time - $start > 0.3)
}


sub recent_changes_ {
    state $log = VNWeb::Misc::Changes::changes->[0];
    state $logmsg = $log && bb_format $log->[2], inline => 1, maxlength => 150;
    my $haslog = $log && $log->[0] >= strftime('%Y%m%d', gmtime)-2;
    my($lst) = VNWeb::Misc::History::fetch(undef, {m=>1,h=>1,p=>1}, {results=>$haslog?9:10});

    p_ class => 'mainopts', sub {
        a_ href => '/changes', 'Site changes';
    };
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
        li_ sub {
            span_ sub {
                lit_ 'vndb:';
                a_ href => "/changes#$log->[1]", sub {
                    rdate_ $log->[0];
                    lit_ $log->[1] =~ s/^[0-9]+//r;
                };
                lit_ ' - ';
                lit_ $logmsg;
            };
        } if $haslog;
    };
}


sub recent_db_posts_ {
    my $an = fu->sql("
        SELECT t.id, t.title
          FROM threads t
          JOIN threads_boards tb ON tb.tid = t.id AND tb.type = 'an'
          JOIN threads_posts tp ON tp.tid = t.id AND tp.num = 1
         WHERE NOT t.hidden AND NOT t.private AND tp.date > NOW() - interval '30 days'
         ORDER BY tb.tid DESC
         LIMIT 2"
    )->allh;
    my $lst = fu->SQL('
        SELECT t.id, t.title, tp.num, tp.date, ', USER, '
          FROM threads t
          JOIN threads_posts tp ON tp.tid = t.id AND tp.num = t.c_lastnum
          LEFT JOIN users u ON tp.uid = u.id
         WHERE EXISTS(SELECT 1 FROM threads_boards tb WHERE tb.tid = t.id AND tb.type IN(\'db\',\'an\'))
           AND NOT t.hidden AND NOT t.private
         ORDER BY tp.date DESC
         LIMIT', 10-@$an
    )->allh;
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
    my $lst = fu->SQL('
        WITH tposts (id,title,num,date,uid) AS (
            SELECT t.id, ARRAY[NULL, t.title], tp.num, tp.date, tp.uid
              FROM threads t
              JOIN threads_posts tp ON tp.tid = t.id AND tp.num = t.c_lastnum
             WHERE NOT EXISTS(SELECT 1 FROM threads_boards tb WHERE tb.tid = t.id AND tb.type IN(\'an\',\'db\',\'u\'))
               AND NOT t.hidden AND NOT t.private
             ORDER BY tp.date DESC LIMIT 10
        ), wposts (id,vid,num,date,uid) AS (
            SELECT w.id, w.vid, wp.num, wp.date, wp.uid
              FROM reviews w
              JOIN reviews_posts wp ON wp.id = w.id AND wp.num = w.c_lastnum
             WHERE NOT w.c_flagged AND wp.hidden IS NULL
             ORDER BY wp.date DESC LIMIT 10
        ), wposts_title (id,title,num,date,uid) AS (
            SELECT w.id, v.title, w.num, w.date, w.uid
              FROM wposts w
              JOIN', VNT, 'v ON v.id = w.vid
        ) SELECT x.id, x.num, x.title, x.date,', USER, '
            FROM (SELECT * FROM tposts UNION ALL SELECT * FROM wposts_title) x
            LEFT JOIN users u ON u.id = x.uid
           ORDER BY date DESC
           LIMIT 10'
    )->allh;
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



sub releases($released) {
    my $filt = advsearch_default 'r';

    # Drop any top-level date filters
    $filt->{query} = [ grep !(ref $_ eq 'ARRAY' && $_->[0] eq 'released'), $filt->{query}->@* ] if $filt->{query};
    delete $filt->{query} if $filt->{query} && ($filt->{query}[0] eq 'released' || $filt->{query}->@* < 2);
    my $has_saved = !!$filt->{query};

    # Add the release date as filter, we need to construct a filter for the header link anyway
    $filt->{query} = [ 'and', [ released => $released ? '<=' : '>', 1 ], $filt->{query} || () ];

    my $start = time;
    my $lst = fu->SQL('
        SELECT id, title, released
          FROM', RELEASEST, 'r
         WHERE NOT hidden AND ', $filt->WHERE, '
           AND NOT EXISTS(SELECT 1 FROM releases_titles rt WHERE rt.id = r.id AND rt.mtl)
         ORDER BY released', $released ? 'DESC' : '', ', id LIMIT 10'
    )->allh;
    my $end = time;
    fu->enrich(aov => 'plat', 'SELECT id, platform FROM releases_platforms WHERE id', $lst);
    fu->enrich(aov => 'lang', 'SELECT id, lang     FROM releases_titles    WHERE id', $lst);
    ($lst, $filt, $has_saved && $end-$start > 0.3)
}


sub releases_ {
    my($lst, $filt, $released) = @_;

    h1_ sub {
        a_ href => '/r?f='.$filt->enc_query().'&o=a&s=released', 'Upcoming Releases' if !$released;
        a_ href => '/r?f='.$filt->enc_query().'&o=d&s=released', 'Just Released' if $released;
    };
    ul_ sub {
        li_ sub {
            span_ sub {
                rdate_ $_->{released};
                txt_ ' ';
                my $icons = $_->{plat}->@* + $_->{lang}->@*;
                platform_ $_
                    for @{$_->{plat}}[0 .. min $#{$_->{plat}}, $icons > 5 ? 2 : 5];
                abbr_ class => "icon-lang-$_", title => $LANGUAGE{$_}{txt}, ''
                    for @{$_->{lang}}[0.. min $#{$_->{lang}}, $icons > 5 ? max 1, 4 - $_->{plat}->@* : 5];
                txt_ $icons > 5 ? '… ' : ' ';
                a_ href => "/$_->{id}", tattr $_;
            }
        } for @$lst;
    };
}


sub reviews_ {
    my $lst = fu->SQL('
        SELECT w.id, v.title, w.length, w.date, ', USER, '
          FROM reviews w
          JOIN', VNT, 'v ON v.id = w.vid
          LEFT JOIN users u ON u.id = w.uid
         WHERE NOT w.c_flagged
         ORDER BY w.id DESC LIMIT 10'
    )->allh;
    h1_ sub {
        a_ href => '/w', 'Latest Reviews';
    };
    ul_ sub {
        li_ sub {
            span_ sub {
                txt_ fmtage($_->{date}).' ';
                small_ ['Short ', 'Med ', 'Long ']->[$_->{length}];
                a_ href => "/$_->{id}", tattr $_;
            };
            span_ sub {
                lit_ 'by ';
                user_ $_;
            }
        } for @$lst;
    }
}


FU::get '/', sub {
    my %meta = (
        'type' => 'website',
        'title' => 'The Visual Novel Database',
        'description' => (config->{moe} ? 'VNDB.moe' : 'VNDB.org').' strives to be a comprehensive database for information about visual novels.',
    );

    my($screens, $slowscreens) = screens;
    my($rel0, $filt0, $slowrel0) = releases 0;
    my($rel1, $filt1, $slowrel1) = releases 1;
    my $slowrel = $slowrel0 || $slowrel1;

    framework_ title => $meta{title}, feeds => 1, og => \%meta, index => 1, sub {
        article_ sub {
            h1_ $meta{title};
            p_ class => 'description', sub {
                txt_ $meta{description};
                br_;
                txt_ config->{moe} ? q{
                  This is a read-only mirror of VNDB.org with a bunch of filters applied.
                  Many features are disabled and 18+-only visual novels are not visible here.
                } : q{
                  This website is built as a wiki, meaning that anyone can freely add
                  and contribute information to the database, allowing us to create the
                  largest, most accurate and most up-to-date visual novel database on the web.
                };
            };
            p_ class => 'screenshots', sub {
                a_ href => "/$_->{vid}", title => $_->{title}[1], sub {
                    my($w, $h) = imgsize $_->{width}, $_->{height}, config->{scr_size}->@*;
                    img_ src => imgurl($_->{id}, 't'), alt => $_->{title}[1], width => $w, height => $h;
                } for @$screens;
            };
            p_ class => 'center standout', sub {
                txt_ 'If VNDB appears to load a little slow for you, try clearing or adjusting your ';
                a_ href => '/v', 'saved visual novel filters' if $slowscreens;
                txt_ ' or ' if $slowscreens && $slowrel;
                a_ href => '/r', 'saved release filters' if $slowrel;
                txt_ '.';
            } if $slowscreens || $slowrel;
        };
        div_ class => 'homepage', sub {
            if(!config->{moe}) {
                article_ \&recent_changes_;
                article_ \&recent_db_posts_;
                article_ \&recent_vn_posts_;
            }
            article_ sub { reviews_ };
            article_ sub { releases_ $rel0, $filt0, 0 };
            article_ sub { releases_ $rel1, $filt1, 1 };
        };
    };
};

1;
