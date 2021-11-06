package VNWeb::Producers::List;

use VNWeb::Prelude;
use VNWeb::AdvSearch;


sub listing_ {
    my($opt, $list, $count) = @_;

    my sub url { '?'.query_encode %$opt, @_ }

    paginate_ \&url, $opt->{p}, [$count, 150], 't';
    div_ class => 'mainbox producerbrowse', sub {
        h1_ $opt->{q} ? 'Search results' : 'Browse producers';
        ul_ sub {
            li_ sub {
                abbr_ class => "icons lang $_->{lang}", title => $LANGUAGE{$_->{lang}}, '';
                a_ href => "/$_->{id}", title => $_->{original}||$_->{name}, $_->{name};
            } for @$list;
        }
    };
    paginate_ \&url, $opt->{p}, [$count, 150], 'b';
}


TUWF::get qr{/p(?:/(?<char>all|[a-z0]))?}, sub {
    my $char = tuwf->capture('char');
    my $opt = tuwf->validate(get =>
        p => { upage => 1 },
        q => { onerror => '' },
        f => { advsearch_err => 'p' },
        ch=> { onerror => [], type => 'array', scalar => 1, values => { onerror => undef, enum => ['0', 'a'..'z'] } },
    )->data;
    $opt->{ch} = $opt->{ch}[0];

    # compat with old URLs
    my $oldch = tuwf->capture('char');
    $opt->{ch} //= $oldch if defined $oldch && $oldch ne 'all';

    $opt->{f} = advsearch_default 'p' if !$opt->{f}{query} && !defined tuwf->reqGet('f');

    my $qs = length $opt->{q} && '%'.sql_like($opt->{q}).'%';
    my $where = sql_and 'NOT p.hidden', $opt->{f}->sql_where(),
        $qs ? sql('p.name ILIKE', \$qs, 'OR p.original ILIKE', \$qs, 'OR p.alias ILIKE', \$qs) : (),
        defined($opt->{ch}) && $opt->{ch} ? sql('LOWER(SUBSTR(p.name, 1, 1)) =', \$opt->{ch}) : (),
        defined($opt->{ch}) && !$opt->{ch} ? sql('(ASCII(p.name) <', \97, 'OR ASCII(p.name) >', \122, ') AND (ASCII(p.name) <', \65, 'OR ASCII(p.name) >', \90, ')') : ();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = tuwf->dbVali('SELECT COUNT(*) FROM producers p WHERE', $where);
        $list = $count ? tuwf->dbPagei({ results => 150, page => $opt->{p} },
            'SELECT p.id, p.name, p.original, p.lang FROM producers p WHERE', $where, 'ORDER BY p.name'
        ) : [];
    } || (($count, $list) = (undef, []));
    $time = time - $time;

    framework_ title => 'Browse producers', sub {
        div_ class => 'mainbox', sub {
            h1_ 'Browse producers';
            form_ action => '/p', method => 'get', sub {
                searchbox_ p => $opt->{q};
                p_ class => 'browseopts', sub {
                    button_ type => 'submit', name => 'ch', value => ($_//''), ($_//'') eq ($opt->{ch}//'') ? (class => 'optselected') : (), !defined $_ ? 'ALL' : $_ ? uc $_ : '#'
                        for (undef, 'a'..'z', 0);
                };
                input_ type => 'hidden', name => 'ch', value => $opt->{ch}//'';
                $opt->{f}->elm_;
                advsearch_msg_ $count, $time;
            };
        };
        listing_ $opt, $list, $count if $count;
    };
};

1;
