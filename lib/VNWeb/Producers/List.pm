package VNWeb::Producers::List;

use VNWeb::Prelude;


sub listing_ {
    my($opt, $list, $count) = @_;

    my sub url { '?'.query_encode %$opt, @_ }

    paginate_ \&url, $opt->{p}, [$count, 150], 't';
    div_ class => 'mainbox producerbrowse', sub {
        h1_ $opt->{q} ? 'Search results' : 'Browse producers';
        if(!@$list) {
            p_ 'No results found.';
        } else {
            ul_ sub {
                li_ sub {
                    abbr_ class => "icons lang $_->{lang}", title => $LANGUAGE{$_->{lang}}, '';
                    a_ href => "/$_->{id}", title => $_->{original}||$_->{name}, $_->{name};
                } for @$list;
            }
        }
    };
    paginate_ \&url, $opt->{p}, [$count, 150], 'b';
}


TUWF::get qr{/p/(?<char>all|[a-z0])}, sub {
    my $char = tuwf->capture('char');
    my $opt = tuwf->validate(get =>
        p => { upage => 1 },
        q => { onerror => '' },
    )->data;

    my $qs = defined $opt->{q} && '%'.sql_like($opt->{q}).'%';
    my $where = sql_and 'NOT p.hidden',
        $qs ? sql 'p.name ILIKE', \$qs, 'OR p.original ILIKE', \$qs, 'OR p.alias ILIKE', \$qs : (),
        $char eq 0 ? "ascii(p.name) not between ascii('a') and ascii('z') AND ascii(p.name) not between ascii('A') and ascii('Z')" :
        $char ne 'all' ? sql 'p.name ILIKE', \"$char%" : ();

    my $count = tuwf->dbVali('SELECT COUNT(*) FROM producers p WHERE', $where);
    my $list = tuwf->dbPagei({ results => 150, page => $opt->{p} },
        'SELECT p.id, p.name, p.original, p.lang FROM producers p WHERE', $where, 'ORDER BY p.name'
    );

    framework_ title => 'Browse producers', sub {
        div_ class => 'mainbox', sub {
            h1_ 'Browse producers';
            form_ action => '/p/all', method => 'get', sub {
                searchbox_ p => $opt->{q};
            };
            p_ class => 'browseopts', sub {
                a_ href => "/p/$_", $_ eq $char ? (class => 'optselected') : (), $_ eq 'all' ? 'ALL' : $_ ? uc $_ : '#'
                    for ('all', 'a'..'z', 0);
            };
        };
        listing_ $opt, $list, $count;
    };
};

1;
