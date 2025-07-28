package VNWeb::Misc::ExtLinks;

use VNWeb::Prelude;
use FU::Util 'uri_escape';


sub fmtage2($t) { fmtage($t) =~ s/ ago//r }

sub heading_ {
    h1_ 'Link Fetching Status';
    p_ sub {
        strong_ 'EXPERIMENTAL!';
        ul_ sub {
            li_ 'This feature is still in development, a lot of functionality is still missing.';
            li_ 'Only a few known websites are being checked for now, this list is likely to expand in the future.';
            li_ 'Link checking is inherently messy and relies on shitty heuristics, links may get flagged as dead even if they are still alive and vice versa.';
            li_ 'Always manually verify a link before editing the database.';
        };
    };
    p_ class => 'center', sub {
        strong_ 'Queues' if fu->path eq '/el/queues';
        a_ href => '/el/queues', 'Queues' if fu->path ne '/el/queues';
        small_ ' | ';
        strong_ 'Links' if fu->path eq '/el';
        a_ href => '/el', 'Links' if fu->path ne '/el';
    };
}

FU::get '/el/queues', sub {
    fu->denied if !auth;

    my $lst = fu->sql('
        SELECT queue, count(*) cnt, count(*) filter (where deadsince is not null) dead, min(lastfetch) oldest
          FROM extlinks
         WHERE queue IS NOT NULL
         GROUP BY queue
         ORDER BY queue
    ')->allh;

    framework_ title => 'Link Fetching Status', sub {
        article_ sub {
            heading_;
        };
        article_ class => 'browse', sub {
            table_ class => 'stripe', sub {
                thead_ sub { tr_ sub {
                    td_ class => 'tc1', 'Queue';
                    td_ '#Links';
                    td_ '#Dead';
                    td_ 'Lag';
                } };
                tr_ sub {
                    td_ class => 'tc1', sub {
                        a_ href => '/el?qu='.uri_escape($_->{queue}), $_->{queue};
                    };
                    td_ $_->{cnt};
                    td_ sub {
                        lit_ '-' if !$_->{dead};
                        a_ href => '/el?de=1&qu='.uri_escape($_->{queue}),
                            sprintf '%d (%.1f%%)', $_->{dead}, $_->{dead}/$_->{cnt}*100 if $_->{dead};
                    };
                    td_ fmtage2 $_->{oldest};
                } for @$lst;
            }
        };
    };
};


sub listing_($opt, $list, $count) {
    my sub url { '?'.query_encode({%$opt, @_}) }

    paginate_ \&url, $opt->{p}, [$count, 50], 't';
    article_ class => 'browse', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub { 
                td_ class => 'tc1', 'Link';
                td_ sub { txt_ 'Last fetch'; sortable_ 'fetch', $opt, \&url };
                td_ sub { txt_ 'Dead for'; sortable_ 'dead', $opt, \&url };
                td_ 'Entry';
            } };
            tr_ sub {
                my $l = $VNDB::ExtLinks::LINKS{$_->{site}};
                td_ class => 'tc1', sub {
                    txt_ $l->{label};
                    txt_ ' » ';
                    a_ href => sprintf($l->{fmt}, $_->{value}), $_->{value};
                };
                td_ $_->{lastfetch} ? fmtage $_->{lastfetch} : 'never';
                td_ $_->{deadsince} ? fmtage2 $_->{deadsince} : '-';
                td_ sub {
                    join_ ',', sub {
                        a_ href => "/$_", $_;
                    }, $_->{entry}->@*;
                };
            } for @$list;
        };
    };
    paginate_ \&url, $opt->{p}, [$count, 50], 'b';
}

FU::get '/el', sub {
    fu->denied if !auth;

    my $opt = fu->query(
        s => { onerror => 'fetch', enum => ['fetch', 'dead'] },
        o => { onerror => 'd', enum => ['a', 'd'] },
        p  => { upage => 1 },
        qu => { onerror => '' },
        de => { undefbool => 1 },
    );

    my $where = AND
        'lastfetch < NOW()',
        $opt->{qu} ? SQL 'queue =', $opt->{qu} : 'queue IS NOT NULL',
        $opt->{de} ? 'deadsince IS NOT NULL' : defined $opt->{de} ? 'deadsince IS NULL' : ();

    my $count = fu->SQL('SELECT count(*) FROM extlinks WHERE', $where)->val;
    my $list = $count && fu->SQL('
        SELECT id, site, value, lastfetch, deadsince
          FROM extlinks
         WHERE', $where, '
         ORDER BY', RAW {fetch => 'lastfetch', dead => 'deadsince'}->{$opt->{s}}, RAW {qw|a ASC d DESC|}->{$opt->{o}}, ' NULLS LAST, id
         LIMIT 50 OFFSET', ($opt->{p}-1)*50
    )->allh;

    fu->enrich(aov => entry => sub { SQL '
                 SELECT l.link, l.id FROM releases_extlinks  l JOIN releases  e ON e.id = l.id WHERE NOT e.hidden AND l.link', IN($_), '
       UNION ALL SELECT l.link, l.id FROM producers_extlinks l JOIN producers e ON e.id = l.id WHERE NOT e.hidden AND l.link', IN($_), '
       UNION ALL SELECT l.link, l.id FROM staff_extlinks     l JOIN staff     e ON e.id = l.id WHERE NOT e.hidden AND l.link', IN($_), '
       UNION ALL SELECT l.link, l.id FROM vn_extlinks        l JOIN vn        e ON e.id = l.id WHERE NOT e.hidden AND l.link', IN($_)
    }, $list) if $count;

    framework_ title => 'Link Fetching Status', sub {
        article_ sub {
            heading_;
        };
        listing_ $opt, $list, $count if $count;
    };
};

1;
