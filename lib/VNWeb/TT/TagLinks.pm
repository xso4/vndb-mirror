package VNWeb::TT::TagLinks;

use VNWeb::Prelude;
use VNWeb::TT::Lib;


sub listing_ {
    my($opt, $lst, $np, $url) = @_;

    paginate_ $url, $opt->{p}, $np, 't';
    div_ class => 'mainbox browse taglinks', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                    td_ class => 'tc1', sub { txt_ 'Date'; sortable_ 'date', $opt, $url; debug_ $lst; };
                    td_ class => 'tc2', 'User';
                    td_ class => 'tc3', 'Rating';
                    td_ class => 'tc4', sub { txt_ 'Tag';  sortable_ 'tag', $opt, $url };
                    td_ class => 'tc5', 'Spoiler';
                    td_ class => 'tc6', 'Visual novel';
                    td_ class => 'tc7', 'Note';
                }};
            tr_ sub {
                my $i = $_;
                td_ class => 'tc1', fmtdate $i->{date};
                td_ class => 'tc2', sub {
                    a_ href => $url->(u => $i->{uid}, p=>undef), class => 'setfil', '> ' if $i->{uid} && !defined $opt->{u};
                    user_ $i;
                };
                td_ class => 'tc3', sub { tagscore_ $i->{vote}, $i->{ignore} };
                td_ class => 'tc4', sub {
                    a_ href => $url->(t => $i->{tag}, p=>undef), class => 'setfil', '> ' if !defined $opt->{t};
                    a_ href => "/$i->{tag}", $i->{name};
                };
                td_ class => 'tc5', sub {
                    my $s = !defined $i->{spoiler} ? '' : $i->{lie} ? 'False' : fmtspoil $i->{spoiler};
                    b_ class => 'grayedout', $s if $i->{ignore};
                    txt_ $s if !$i->{ignore};
                };
                td_ class => 'tc6', sub {
                    a_ href => $url->(v => $i->{vid}, p=>undef), title => $i->{alttitle}||$i->{title}, class => 'setfil', '> ' if !defined $opt->{v};
                    a_ href => "/$i->{vid}", title => $i->{alttitle}||$i->{title}, shorten $i->{title}, 50;
                };
                td_ class => 'tc7', sub { lit_ bb_format $i->{notes}, inline => 1 };
            } for @$lst;
        };
    };
    paginate_ $url, $opt->{p}, $np, 'b';
}


TUWF::get qr{/g/links}, sub {
    my $opt = tuwf->validate(get =>
        p => { page => 1 },
        o => { onerror => 'd', enum => ['a', 'd'] },
        s => { onerror => 'date', enum => [qw|date tag|] },
        v => { onerror => undef, vndbid => 'v' },
        u => { onerror => undef, vndbid => 'u' },
        t => { onerror => undef, vndbid => 'g' },
    )->data;

    my $where = sql_and
        defined $opt->{v} ? sql('tv.vid =', \$opt->{v}) : (),
        defined $opt->{u} ? sql('tv.uid =', \$opt->{u}) : (),
        defined $opt->{t} ? sql('tv.tag =', \$opt->{t}) : ();

    my $filt = defined $opt->{u} || defined $opt->{t} || defined $opt->{v};

    my $count = $filt && tuwf->dbVali('SELECT COUNT(*) FROM tags_vn tv WHERE', $where);
    my($lst, $np) = tuwf->dbPagei({ page => $opt->{p}, results => 50 }, '
        SELECT tv.vid, tv.uid, tv.tag, tv.vote, tv.spoiler, tv.lie,', sql_totime('tv.date'), 'as date
             , tv.ignore OR (u.id IS NOT NULL AND NOT u.perm_tag) AS ignore, tv.notes, v.title, v.alttitle, ', sql_user(), ', t.name
          FROM tags_vn tv
          JOIN vnt v ON v.id = tv.vid
          LEFT JOIN users u ON u.id = tv.uid
          JOIN tags t ON t.id = tv.tag
         WHERE', $where, '
         ORDER BY', { date => 'tv.date', tag => 't.name' }->{$opt->{s}}, { a => 'ASC', d => 'DESC' }->{$opt->{o}}
    );
    $np = [ $count, 50 ] if $count;

    my sub url { '?'.query_encode %$opt, @_ }

    framework_ title => 'Tag link browser', sub {
        div_ class => 'mainbox', sub {
            h1_ 'Tag link browser';
            if($filt) {
                p_ 'Active filters:';
                ul_ sub {
                    li_ sub {
                        txt_ '['; a_ href => url(u=>undef, p=>undef), 'remove'; txt_ '] ';
                        txt_ 'User: ';
                        user_ tuwf->dbRowi('SELECT', sql_user(), 'FROM users u WHERE id=', \$opt->{u});
                    } if defined $opt->{u};
                    li_ sub {
                        txt_ '['; a_ href => url(t=>undef, p=>undef), 'remove'; txt_ '] ';
                        txt_ 'Tag:'; txt_ ' ';
                        a_ href => "/$opt->{t}", tuwf->dbVali('SELECT name FROM tags WHERE id=', \$opt->{t})||'Unknown tag';
                    } if defined $opt->{t};
                    li_ sub {
                        txt_ '['; a_ href => url(v=>undef, p=>undef), 'remove'; txt_ '] ';
                        txt_ 'Visual novel'; txt_ ' ';
                        my $v = tuwf->dbRowi('SELECT title, alttitle FROM vnt WHERE id=', \$opt->{v});
                        a_ href => "/$opt->{v}", title => $v->{alttitle}||$v->{title}, $v->{title}||'Unknown VN';
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
