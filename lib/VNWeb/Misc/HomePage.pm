package VNWeb::Misc::HomePage;

use VNWeb::Prelude;
use VNWeb::Filters;
use VNWeb::Discussions::Lib 'enrich_boards';
use POSIX 'strftime';


sub screens_ {
    state $where  ||= sql 'i.c_weight > 0 and vndbid_type(i.id) =', \'sf', 'and i.c_sexual_avg <', \0.4, 'and i.c_violence_avg <', \0.4;
    state $stats  ||= tuwf->dbRowi('SELECT count(*) as total, count(*) filter(where', $where, ') as subset from images i');
    state $sample ||= 100*min 1, (200 / $stats->{subset}) * ($stats->{total} / $stats->{subset});

    my $filt = auth->pref('filter_vn') && eval { filter_parse v => auth->pref('filter_vn') };
    my $lst = $filt ? tuwf->dbAlli(
        # Assumption: If we randomly select 30 matching VNs, there'll be at least 4 VNs with qualified screenshots
        # (As of Sep 2020, over half of the VNs in the database have screenshots, so that assumption usually works)
        'SELECT * FROM (
            SELECT DISTINCT ON (v.id) i.id, i.width, i,height, v.id AS vid, v.title
              FROM (SELECT id, title FROM vn v WHERE NOT v.hidden AND ', filter_vn_query($filt), ' ORDER BY random() LIMIT', \30, ') v
              JOIN vn_screenshots vs ON v.id = vs.id
              JOIN images i ON i.id = vs.scr
             WHERE ', $where, '
             ORDER BY v.id
        ) x ORDER BY random() LIMIT', \4
    ) : tuwf->dbAlli('
        SELECT i.id, i.width, i.height, v.id AS vid, v.title
          FROM (SELECT id, width, height FROM images i TABLESAMPLE SYSTEM (', \$sample, ') WHERE', $where, ' ORDER BY random() LIMIT', \4, ') i(id)
          JOIN vn_screenshots vs ON vs.scr = i.id
          JOIN vn v ON v.id = vs.id
         ORDER BY random()
         LIMIT', \4
    );

    p_ class => 'screenshots', sub {
        a_ href => "/v$_->{vid}", title => $_->{title}, sub {
            my($w, $h) = imgsize $_->{width}, $_->{height}, tuwf->{scr_size}->@*;
            img_ src => tuwf->imgurl($_->{id}, 1), alt => $_->{title}, width => $w, height => $h;
        } for @$lst;
    }
}


sub recent_changes_ {
    my($lst) = VNWeb::Misc::History::fetch(undef, undef, {m=>1,h=>1,p=>1}, {results=>10});
    h1_ sub {
        a_ href => '/hist', 'Recent Changes'; txt_ ' ';
        a_ href => '/feeds/changes.atom', sub { abbr_ class => 'icons feed', title => 'Atom Feed', '' };
    };
    ul_ sub {
        li_ sub {
            txt_ "$_->{type}:";
            a_ href => "/$_->{type}$_->{itemid}.$_->{rev}", title => $_->{original}||$_->{title}, shorten $_->{title}, 33;
            lit_ " by ";
            user_ $_;
        } for @$lst;
    };
}


sub announcements_ {
    my $lst = tuwf->dbAlli('
        SELECT t.id, t.title, substring(tp.msg, 1, 100+100+100) AS msg
          FROM threads t
          JOIN threads_boards tb ON tb.tid = t.id AND tb.type = \'an\'
          JOIN threads_posts tp ON tp.tid = t.id AND tp.num = 1
         WHERE NOT t.hidden AND NOT t.private
         ORDER BY tb.tid DESC
         LIMIT 1+1'
    );
    h1_ sub {
        a_ href => '/t/an', 'Announcements'; txt_ ' ';
        a_ href => '/feeds/announcements.atom', sub { abbr_ class => 'icons feed', title => 'Atom Feed', '' };
    };
    for (@$lst) {
        h2_ sub { a_ href => "/$_->{id}", $_->{title} };
        p_ sub { lit_ bb_format $_->{msg}, maxlength => 150, inline => 1 };
    }
}


sub recent_posts_ {
    my $lst = tuwf->dbAlli('
        SELECT t.id, t.title, tp.num,', sql_totime('tp.date'), 'AS date, ', sql_user(), '
          FROM threads t
          JOIN threads_posts tp ON tp.tid = t.id AND tp.num = t.c_lastnum
          LEFT JOIN users u ON tp.uid = u.id
         WHERE NOT EXISTS(SELECT 1 FROM threads_boards tb WHERE tb.tid = t.id AND tb.type = \'u\')
           AND NOT t.hidden AND NOT t.private
         ORDER BY tp.date DESC
         LIMIT 10'
    );
    enrich_boards undef, $lst;
    h1_ sub {
        a_ href => '/t/all', 'Recent Posts'; txt_ ' ';
        a_ href => '/feeds/posts.atom', sub { abbr_ class => 'icons feed', title => 'Atom Feed', ''; };
    };
    ul_ sub {
        li_ sub {
            my $boards = join ', ', map $BOARD_TYPE{$_->{btype}}{txt}.($_->{iid}?' > '.$_->{title}:''), $_->{boards}->@*;
            txt_ fmtage($_->{date}).' ';
            a_ href => "/$_->{id}.$_->{num}#last", title => "Posted in $boards", shorten $_->{title}, 25;
            lit_ ' by ';
            user_ $_;
        } for @$lst;
    };
}


sub random_vns_ {
    state $stats  ||= tuwf->dbRowi('SELECT COUNT(*) AS total, COUNT(*) FILTER(WHERE NOT hidden) AS subset FROM vn');
    state $sample ||= 100*min 1, (100 / $stats->{subset}) * ($stats->{total} / $stats->{subset});

    my $filt = auth->pref('filter_vn') && eval { filter_parse v => auth->pref('filter_vn') };
    my $lst = tuwf->dbAlli('
        SELECT id, title, original
          FROM vn v', $filt ? '' : ('TABLESAMPLE SYSTEM (', \$sample, ')'), '
         WHERE NOT hidden AND', filter_vn_query($filt||{}), '
         ORDER BY random() LIMIT 10'
    );

    h1_ sub {
        a_ href => '/v/rand', 'Random visual novels';
    };
    ul_ sub {
        li_ sub {
            a_ href => "/v$_->{id}", title => $_->{original}||$_->{title}, shorten $_->{title}, 40;
        } for @$lst;
    }
}


sub releases_ {
    my($released) = @_;

    my $filt = auth->pref('filter_release') && eval { filter_parse r => auth->pref('filter_release') };
    $filt = { $filt ? %$filt : (), date_before => undef, date_after => undef, released => $released?1:0 };

    # XXX This query is kinda slow, an index on releases.released would probably help.
    my $lst = tuwf->dbAlli('
        SELECT id, title, original, released
          FROM releases r
         WHERE NOT hidden AND released', $released ? '<=' : '>', \strftime('%Y%m%d', gmtime), '
           AND ', filter_release_query($filt), '
         ORDER BY released', $released ? 'DESC' : '', ', id LIMIT 10'
    );
    enrich_flatten plat => id => id => 'SELECT id, platform FROM releases_platforms WHERE id IN', $lst;
    enrich_flatten lang => id => id => 'SELECT id, lang     FROM releases_lang      WHERE id IN', $lst;

    h1_ sub {
        a_ href => '/r?fil='.VNDB::Func::fil_serialize($filt).';o=a;s=released', 'Upcoming Releases' if !$released;
        a_ href => '/r?fil='.VNDB::Func::fil_serialize($filt).';o=d;s=released', 'Just Released' if $released;
    };
    ul_ sub {
        li_ sub {
            rdate_ $_->{released};
            txt_ ' ';
            abbr_ class => "icons $_", title => $PLATFORM{$_}, '' for $_->{plat}->@*;
            abbr_ class => "icons lang $_", title => $LANGUAGE{$_}, '' for $_->{lang}->@*;
            txt_ ' ';
            a_ href => "/r$_->{id}", title => $_->{original}||$_->{title}, shorten $_->{title}, 30;
        } for @$lst;
    };
}


sub reviews_ {
    my($full) = @_;
    my $lst = tuwf->dbAlli('
        SELECT w.id, v.title,', sql_user(), ',', sql_totime('w.date'), 'AS date
          FROM reviews w
          JOIN vn v ON v.id = w.vid
          LEFT JOIN users u ON u.id = w.uid
         WHERE ', $full ? '' : 'NOT', 'w.isfull
         ORDER BY w.id DESC LIMIT 10'
    );
    h1_ sub {
        a_ href => '/w', $full ? 'Latest Full Reviews' : 'Latest Mini Reviews';
    };
    ul_ sub {
        li_ sub {
            txt_ fmtage($_->{date}).' ';
            a_ href => "/$_->{id}", title => $_->{title}, shorten $_->{title}, 25;
            lit_ ' by ';
            user_ $_;
        } for @$lst;
    }
}


sub recent_comments_ {
    my $lst = tuwf->dbAlli('
        SELECT w.id, wp.num, v.title,', sql_user(), ',', sql_totime('wp.date'), 'AS date
          FROM reviews w
          JOIN reviews_posts wp ON wp.id = w.id AND wp.num = w.c_lastnum
          JOIN vn v ON v.id = w.vid
          LEFT JOIN users u ON u.id = wp.uid
         ORDER BY wp.date DESC LIMIT 10'
    );
    h1_ sub {
        a_ href => '/w?s=lastpost', 'Recent Review Comments';
    };
    ul_ sub {
        li_ sub {
            txt_ fmtage($_->{date}).' ';
            a_ href => "/$_->{id}.$_->{num}#last", title => $_->{title}, shorten $_->{title}, 25;
            lit_ ' by ';
            user_ $_;
        } for @$lst;
    };
}


TUWF::get qr{/}, sub {
    my %meta = (
        'type' => 'website',
        'title' => 'The Visual Novel Database',
        'description' => 'VNDB.org strives to be a comprehensive database for information about visual novels.',
    );

    framework_ title => $meta{title}, feeds => 1, og => \%meta, index => 1, sub {
        div_ class => 'mainbox', sub {
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
        table_ class => 'mainbox threelayout', sub {
            tr_ sub {
                td_ \&recent_changes_;
                td_ \&announcements_;
                td_ \&recent_posts_;
            };
            tr_ sub {
                td_ \&random_vns_;
                td_ sub { releases_ 0 };
                td_ sub { releases_ 1 };
            };
            tr_ sub {
                td_ sub { reviews_ 0 };
                td_ sub { reviews_ 1 };
                td_ \&recent_comments_;
            };
        };
    };
};

1;
