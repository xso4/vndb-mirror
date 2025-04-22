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

    my $u = $opt->{u} && fu->dbRowi('SELECT id,', sql_user(), 'FROM users u WHERE id =', \$opt->{u});
    fu->notfound if $opt->{u} && (!$u->{id} || (!defined $u->{user_name} && !auth->isMod));

    my $where = sql_and
        defined $opt->{v} ? sql('tv.vid =', \$opt->{v}) : (),
        defined $opt->{u} ? sql('tv.uid =', \$opt->{u}) : (),
        defined $opt->{t} ? sql('tv.tag =', \$opt->{t}) : ();

    my $count = $filt && fu->dbVali('SELECT COUNT(*) FROM tags_vn tv WHERE', $where);
    my($lst, $np) = fu->dbPagei({ page => $opt->{p}, results => 50 }, '
        SELECT tv.vid, tv.uid, tv.tag, tv.vote, tv.spoiler, tv.lie,', sql_totime('tv.date'), 'as date
             , tv.ignore OR (u.id IS NOT NULL AND NOT u.perm_tag) AS ignore, tv.notes, v.title, ', sql_user(), ', t.name
          FROM tags_vn tv
          JOIN', vnt, 'v ON v.id = tv.vid
          LEFT JOIN users u ON u.id = tv.uid
          JOIN tags t ON t.id = tv.tag
         WHERE', $where, '
         ORDER BY', sprintf { date => 'tv.date %s, tv.vid, tv.tag', tag => 't.name %s, tv.vid, tv.uid' }->{$opt->{s}}, { a => 'ASC', d => 'DESC' }->{$opt->{o}}
    );
    $np = [ $count, 50 ] if $count;

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
                        txt_ 'Tag:'; txt_ ' ';
                        a_ href => "/$opt->{t}", fu->dbVali('SELECT name FROM tags WHERE id=', \$opt->{t})||'Unknown tag';
                    } if defined $opt->{t};
                    li_ sub {
                        txt_ '['; a_ href => url(v=>undef, p=>undef), 'remove'; txt_ '] ';
                        txt_ 'Visual novel'; txt_ ' ';
                        my $v = fu->dbRowi('SELECT title FROM', vnt, 'v WHERE id=', \$opt->{v});
                        a_ href => "/$opt->{v}", $v->{title} ? tattr $v : ('Unknown VN');
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
