package VNWeb::TT::TagLinks;

use VNWeb::Prelude;
use VNWeb::TT::Lib;


sub listing_($opt, $lst, $np, $url) {
    paginate_ $url, $opt->{p}, $np, 't';
    article_ class => 'browse taglinks', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                    td_ class => 'tc1', sub { txt_ 'Date'; sortable_ 'date', $opt, $url; debug_ $lst; };
                    td_ class => 'tc2', 'User';
                    td_ class => 'tc3', 'Rating';
                    td_ class => 'tc4', sub { txt_ 'Tag';  sortable_ 'tag', $opt, $url };
                    td_ class => 'tc5', 'Spoiler';
                    td_ class => 'tc6', 'Lie';
                    td_ class => 'tc7', 'Visual novel';
                    td_ class => 'tc8', 'Note';
                }};
            tr_ sub {
                my $i = $_;
                td_ class => 'tc1', fmtdate $i->{date};
                td_ class => 'tc2', sub {
                    a_ href => $url->(u => $i->{uid}, p=>undef), class => 'setfil', '> ' if $i->{uid} && !defined $opt->{u} && (defined $i->{user_name} || auth->isMod);
                    user_ $i;
                };
                td_ class => 'tc3', sub { tagscore_ $i->{vote}, $i->{ignore} };
                td_ class => 'tc4', sub {
                    a_ href => $url->(t => $i->{tag}, p=>undef), class => 'setfil', '> ' if !defined $opt->{t};
                    a_ href => "/$i->{tag}", $i->{name};
                };
                td_ class => 'tc5', sub {
                    my $s = !defined $i->{spoiler} ? '' : fmtspoil $i->{spoiler};
                    small_ $s if $i->{ignore};
                    txt_ $s if !$i->{ignore};
                };
                td_ class => 'tc6', sub {
                    my $s = !defined $i->{lie} ? '' : $i->{lie} ? '+' : '-';
                    small_ $s if $i->{ignore};
                    txt_ $s if !$i->{ignore};
                };
                td_ class => 'tc7', sub {
                    a_ href => $url->(v => $i->{vid}, p=>undef), class => 'setfil', '> ' if !defined $opt->{v};
                    a_ href => "/$i->{vid}", tattr $i;
                };
                td_ class => 'tc8', sub { lit_ bb_format $i->{notes}, inline => 1 };
            } for @$lst;
        };
    };
    paginate_ $url, $opt->{p}, $np, 'b';
}


FU::get '/g/links', sub {
    not_moe;
    my $opt = fu->query(
        o => { onerror => 'd', enum => ['a', 'd'] },
        s => { onerror => 'date', enum => [qw|date tag|] },
        v => { onerror => undef, vndbid => 'v' },
        u => { onerror => undef, vndbid => 'u' },
        t => { onerror => undef, vndbid => 'g' },
    );
    # Allow full browsing when a filter is enabled, but limit the page count if not.
    my $filt = defined $opt->{u} || defined $opt->{t} || defined $opt->{v};
    $opt->{p} = fu->query(p => $filt ? { upage => 1 } : { page => 1 });

    my $u = $opt->{u} && fu->SQL('SELECT id,', USER, 'FROM users u WHERE id =', $opt->{u})->rowh;
    fu->notfound if $opt->{u} && (!$u->{id} || (!defined $u->{user_name} && !auth->isMod));

    my $where = AND
        defined $opt->{v} ? SQL 'tv.vid =', $opt->{v} : (),
        defined $opt->{u} ? SQL 'tv.uid =', $opt->{u} : (),
        defined $opt->{t} ? SQL 'tv.tag =', $opt->{t} : ();

    my $count = $filt && fu->SQL('SELECT COUNT(*) FROM tags_vn tv WHERE', $where)->val;
    my $lst = fu->SQL('
        SELECT tv.vid, tv.uid, tv.tag, tv.vote, tv.spoiler, tv.lie, tv.date
             , tv.ignore OR (u.id IS NOT NULL AND NOT u.perm_tag) AS ignore, tv.notes, v.title, ', USER, ', t.name
          FROM tags_vn tv
          JOIN', VNT, 'v ON v.id = tv.vid
          LEFT JOIN users u ON u.id = tv.uid
          JOIN tags t ON t.id = tv.tag
         WHERE', $where, '
         ORDER BY', RAW(sprintf { date => 'tv.date %s, tv.vid, tv.tag', tag => 't.name %s, tv.vid, tv.uid' }->{$opt->{s}}, { a => 'ASC', d => 'DESC' }->{$opt->{o}}), '
         LIMIT', $filt ? 50 : 51, 'OFFSET', 50*($opt->{p}-1)
    )->allh;
    my $np = $filt ? [ $count, 50 ] : @$lst > 50 && !!pop @$lst;

    my sub url { '?'.query_encode({%$opt, @_}) }

    framework_ title => 'Tag link browser', sub {
        article_ sub {
            h1_ 'Tag link browser';
            if($filt) {
                p_ 'Active filters:';
                ul_ sub {
                    li_ sub {
                        txt_ '['; a_ href => url(u=>undef, p=>undef), 'remove'; txt_ '] ';
                        txt_ 'User: ';
                        user_ $u;
                    } if defined $opt->{u};
                    li_ sub {
                        txt_ '['; a_ href => url(t=>undef, p=>undef), 'remove'; txt_ '] ';
                        txt_ 'Tag: ';
                        a_ href => "/$opt->{t}", fu->sql('SELECT name FROM tags WHERE id= $1', $opt->{t})->val||'Unknown tag';
                    } if defined $opt->{t};
                    li_ sub {
                        txt_ '['; a_ href => url(v=>undef, p=>undef), 'remove'; txt_ '] ';
                        txt_ 'Visual novel: ';
                        my $v = fu->SQL('SELECT title FROM', VNT, 'v WHERE id=', $opt->{v})->val;
                        a_ href => "/$opt->{v}", $v ? tattr $v : ('Unknown VN');
                    } if defined $opt->{v};
                }
            }
            if($lst && @$lst) {
                br_;
                p_ 'Click the arrow before a user, tag or VN to add it as a filter.'
                    unless defined $opt->{u} && defined $opt->{t} && defined $opt->{v};
            } else {
                br_;
                p_ 'No tag votes matching the requested filters.';
            }
        };

        listing_ $opt, $lst, $np, \&url if $lst && @$lst;
    };
};

1;
