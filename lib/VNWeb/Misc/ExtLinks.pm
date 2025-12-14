package VNWeb::Misc::ExtLinks;

use VNWeb::Prelude;
use VNDB::ExtLinks 'extlink_parse', 'extlink_split', 'extlink_fmt', '%LINKS';
use VNDB::Func 'fmtinterval';
use FU::Util 'uri_escape', 'json_format';
use experimental 'builtin';


js_api ExtlinkParse => { url => {} }, sub($data) {
    my($s,$v,$d) = extlink_parse $data->{url};
    +{ res => $s ? { site => $s, value => $v, data => $d, split => extlink_split($s,$v,$d) } : undef }
};

my @FLAGS = qw/redirect unrecognized serverror/;


FU::get '/el/queues', sub {
    fu->denied if !auth;

    my $lst = fu->sql(q{
        WITH queues(queue, cnt, dead, backlog, oldest) AS (
            SELECT queue, count(*)
                 , count(*) filter (where deadsince is not null)
                 , count(*) filter (where nextfetch < now())
                 , min(lastfetch) filter (where deadcount is null or deadcount <= 3)
              FROM extlinks
             WHERE queue IS NOT NULL
             GROUP BY queue
         ) SELECT queues.*, extract('epoch' from tasks.delay)::bigint AS delay
             FROM queues
             LEFT JOIN tasks ON tasks.id = queues.queue
            ORDER BY queues.queue
    })->allh;

    framework_ title => 'Link Fetching Queues', sub {
        article_ sub {
            h1_ 'Link Fetching Queues';
        };
        article_ class => 'browse', sub {
            table_ class => 'stripe extlink-queues', sub {
                thead_ sub { tr_ sub {
                    td_ class => 'tc1', 'Queue';
                    td_ '#Links';
                    td_ '#Dead';
                    td_ 'Backlog';
                    td_ 'Delay';
                    td_ 'Oldest active';
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
                    td_ $_->{backlog};
                    td_ $_->{delay} ? fmtinterval($_->{delay}) : '-';
                    td_ sub { $_->{oldest} ? age2_ $_->{oldest} : lit_ '-' };
                } for @$lst;
            }
        };
    };
};


sub listing_($opt, $list, $count) {
    my sub url { '?'.query_encode({%$opt, @_}) }

    paginate_ \&url, $opt->{p}, [$count, 50], 't';
    article_ class => 'browse extlinks-status', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub { 
                td_ class => 'tc1', 'Link';
                td_ sub { txt_ 'Last fetch'; sortable_ 'fetch', $opt, \&url };
                td_ sub { txt_ 'Dead for'; sortable_ 'dead', $opt, \&url };
                td_ 'Entry';
            } };
            tr_ sub {
                my $l = $_;
                td_ class => 'tc1', sub {
                    a_ href => "/el$l->{id}", "$LINKS{$l->{site}}{label} » $l->{value}";
                };
                td_ $l->{lastfetch} ? sub { age_ $l->{lastfetch} } : 'never';
                my @dead = (
                    $l->{deadsince} ? sub {
                        age2_ $l->{deadsince};
                        txt_ " ($l->{deadcount})";
                    } : (),
                    map { my $x = $_; sub { txt_ $x } } grep $l->{$_}, @FLAGS
                );
                td_ @dead ? sub { join_ ', ', sub { $_->() }, @dead } : '-';
                td_ sub {
                    join_ ',', sub {
                        a_ href => "/$_", $_;
                    }, @{$l->{entry}}[0..min 4, $#{$l->{entry}}];
                    txt_ ',+'.($l->{entry}->@*-5) if $l->{entry}->@* > 5;
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
        ty => { onerror => '', enum => \%LINKS },
        de => { onerror => '', enum => [0,1,2,3] },
        (map +($_ => { onerror => '', enum => [1] }), @FLAGS),
    );

    my $where = AND
        'lastfetch < NOW()',
        $opt->{qu} ? SQL 'queue =', $opt->{qu} : 'queue IS NOT NULL',
        $opt->{ty} ? SQL 'site =', $opt->{ty} : (),
        !length $opt->{de} ? () : $opt->{de} ? SQL 'deadcount >=', $opt->{de} : 'deadcount IS NULL',
        (grep $opt->{$_}, @FLAGS) ? OR(map RAW($_), grep $opt->{$_}, @FLAGS) : ();

    my $count = fu->SQL('SELECT count(*) FROM extlinks WHERE', $where)->val;
    my $list = $count && fu->SQL('
        SELECT id, site, value, data, lastfetch, deadsince, deadcount,', COMMA(map RAW($_), @FLAGS), '
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

    my sub opt_($type, $key, $val, $label) {
        input_ type => $type, name => $key, id => "form_${key}{$val}", value => $val, $opt->{$key} eq $val ? (checked => 'checked') : ();
        label_ for => "form_${key}{$val}", ' '.$label;
    };

    framework_ title => 'Link Fetching Status', sub {
        article_ sub {
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
            form_ sub {
                table_ style => 'margin: auto', sub {
                    tr_ sub {
                        td_ 'Queue';
                        td_ sub {
                            input_ type => 'text', name => 'qu', value => $opt->{qu};
                            txt_ ' ';
                            a_ href => '/el/queues', 'Queue list';
                        }
                    };
                    tr_ sub {
                        td_ 'Type';
                        td_ sub {
                            select_ name => 'ty', sub {
                                option_ value => '', selected => 'selected', '-- all --';
                                option_ value => $_, selected => $opt->{ty} eq $_ ? 'selected' : undef, $LINKS{$_}{label} for sort keys %LINKS;
                            };
                        };
                    };
                    tr_ sub {
                        td_ 'State';
                        td_ sub {
                            opt_ radio => de => '', 'Any'; small_ ' / ';
                            opt_ radio => de => 0, 'Active'; small_ ' / ';
                            opt_ radio => de => 1, 'Dead (1+)'; small_ ' / ';
                            opt_ radio => de => 2, 'Dead (2+)'; small_ ' / ';
                            opt_ radio => de => 3, 'Dead (3+)';
                        };
                    };
                    tr_ sub {
                        td_ 'Flags';
                        td_ sub {
                            join_ sub { small_ ' / ' }, sub { opt_ checkbox => $_ => 1, $_ }, @FLAGS;
                        };
                    };
                    tr_ sub {
                        td_ '';
                        td_ sub { input_ type => 'submit', class => 'submit', value => 'Update' };
                    }
                };
            }
        };
        listing_ $opt, $list, $count if $count;
    };
};


FU::get qr{/el($RE{num})}, sub($id) {
    fu->denied if !auth;

    my $lnk = fu->sql(q{
        SELECT e.id, e.site, e.value, e.data, e.price, e.queue, e.lastfetch, e.nextfetch, e.deadsince, e.deadcount
             , (SELECT COUNT(*) FROM extlinks e2 WHERE e2.queue = e.queue AND e2.nextfetch <= e.nextfetch) AS pos
             , t.sched AS q_sched, extract('epoch' from t.delay)::int AS q_delay
          FROM extlinks e
          LEFT JOIN tasks t ON t.id = e.queue
         WHERE e.c_ref AND e.id = $1}, $id
    )->rowh || fu->notfound;

    my $entries = fu->sql('
                 SELECT l.link, l.id, e.title FROM releases_extlinks  l JOIN releasest    e ON e.id = l.id WHERE NOT e.hidden AND l.link = $1
       UNION ALL SELECT l.link, l.id, e.title FROM producers_extlinks l JOIN producerst   e ON e.id = l.id WHERE NOT e.hidden AND l.link = $1
       UNION ALL SELECT l.link, l.id, e.title FROM staff_extlinks     l JOIN staff_aliast e ON e.id = l.id WHERE NOT e.hidden AND l.link = $1 AND e.main = e.aid
       UNION ALL SELECT l.link, l.id, e.title FROM vn_extlinks        l JOIN vnt          e ON e.id = l.id WHERE NOT e.hidden AND l.link = $1
       ORDER BY id
    ', $id)->allh;

    my $fetch = fu->sql('SELECT id, date, dead, detail FROM extlinks_fetch WHERE id = $1 ORDER BY date DESC LIMIT 50', $id)->allh;

    my $title = "$LINKS{$lnk->{site}}{label} » $lnk->{value}";
    framework_ title => $title, sub {
        article_ sub {
            h1_ $title;
            table_ class => 'extlink-info stripe', sub {
                tr_ sub {
                    td_ 'Type';
                    td_ $LINKS{$lnk->{site}}{label};
                };
                tr_ sub {
                    td_ 'URL';
                    td_ sub {
                        a_ href => extlink_fmt($lnk->{site}, $lnk->{value}, $lnk->{data}), sub {
                            my $i = 0;
                            join_ '', sub {
                                small_ $_ if $i % 2 == 0;
                                txt_ $_ if $i % 2 == 1;
                                $i++;
                            }, extlink_split($lnk->{site}, $lnk->{value}, $lnk->{data})->@*;
                        };
                    };
                };
                tr_ sub {
                    td_ 'Price';
                    td_ $lnk->{price};
                } if $lnk->{price};
                tr_ sub {
                    td_ 'Status';
                    td_ !$lnk->{lastfetch} ? 'Unknown' :
                        !$lnk->{deadsince} ? 'Active' :
                        sprintf 'Dead for %d checks in the past %s', $lnk->{deadcount}, fmtinterval(time - $lnk->{deadsince});
                };
                tr_ sub {
                    td_ 'Last check';
                    td_ $lnk->{lastfetch} ? sub { age_ $lnk->{lastfetch} } : 'Never';
                };
                tr_ sub {
                    td_ 'Next check';
                    td_ $lnk->{queue} ? sub {
                        txt_ "Queued at #$lnk->{pos} in ";
                        a_ href => "/el?qu=$lnk->{queue}", $lnk->{queue};
                        if ($lnk->{q_sched}) {
                            txt_ ' (~';
                            eta_ max $lnk->{nextfetch}, max(time, $lnk->{q_sched}) + max(0, $lnk->{pos}) * $lnk->{q_delay};
                            txt_ ')';
                        } else {
                            txt_ ' (not scheduled)';
                        }
                    } : 'Not queued';
                };
                tr_ sub {
                    td_ 'Linked from';
                    td_ sub {
                        join_ \&br_, sub {
                            small_ $_->{id}.':';
                            a_ href => "/$_->{id}", tattr $_;
                        }, @$entries;
                    };
                };
            };
        };

        return if !@$fetch;
        nav_ sub {
            h1_ 'Check history';
        };
        article_ class => 'browse', sub {
            table_ class => 'stripe extlink-history', sub {
                tr_ sub {
                    my $f = $_;
                    td_ class => 'tc1', sub {
                        abbr_ $f->{dead} ? (class => 'icon-el-dead', title => 'Dead') : (class => 'icon-el-ok', title => 'Active'), '';
                        txt_ fmtdate $f->{date}, 1;
                    };
                    td_ sub {
                        join_ ' ', sub {
                            my($k, $v) = ($_, $f->{detail}{$_});
                            if (builtin::is_bool($v)) {
                                strong_ $k if $v;
                                small_ class => 'linethrough', $k if !$v;
                            } else {
                                strong_ "$k=";
                                txt_ ref $v ? json_format($v) : $v;
                            }
                        }, sort keys $f->{detail}->%*
                    };
                } for @$fetch;
            }
        }
    };
};

1;
