package VNWeb::Producers::List;

use VNWeb::Prelude;
use VNWeb::AdvSearch;


sub listing_($opt, $list, $count) {
    my sub url { '?'.query_encode({%$opt, @_}) }

    paginate_ \&url, $opt->{p}, [$count, 150], 't';
    article_ class => 'producerbrowse', sub {
        h1_ $opt->{q} ? 'Search results' : 'Browse producers';
        ul_ sub {
            li_ sub {
                abbr_ class => "icon-lang-$_->{lang}", title => $LANGUAGE{$_->{lang}}{txt}, '';
                a_ href => "/$_->{id}", tattr $_;
            } for @$list;
        }
    };
    paginate_ \&url, $opt->{p}, [$count, 150], 'b';
}


FU::get qr{/p(?:/(all|[a-z0]))?}, sub($char=undef) {
    my $opt = fu->query(
        p => { upage => 1 },
        q => { searchquery => 1 },
        f => { advsearch_err => 'p' },
        ch=> { onerror => undef, accept_array => 'first', enum => ['0', 'a'..'z'] },
    );

    # compat with old URLs
    $opt->{ch} //= $char if defined $char && $char ne 'all';

    $opt->{f} = advsearch_default 'p' if !$opt->{f}{query} && !defined fu->query('f');

    my $where = sql_and 'NOT p.hidden', $opt->{f}->sql_where(),
        defined($opt->{ch}) ? sql 'match_firstchar(p.sorttitle, ', \$opt->{ch}, ')' : ();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = fu->dbVali('SELECT COUNT(*) FROM', producerst, 'p WHERE', sql_and $where, $opt->{q}->sql_where('p', 'p.id'));
        $list = $count ? fu->dbPagei({ results => 150, page => $opt->{p} },
            'SELECT p.id, p.title, p.lang
               FROM', producerst, 'p', $opt->{q}->sql_join('p', 'p.id'), '
              WHERE', $where, '
              ORDER BY', $opt->{q} ? 'sc.score DESC, ' : (), 'p.sorttitle'
        ) : [];
    } || (($count, $list) = (undef, []));
    $time = time - $time;

    framework_ title => 'Browse producers', sub {
        article_ sub {
            h1_ 'Browse producers';
            form_ action => '/p', method => 'get', sub {
                searchbox_ p => $opt->{q};
                p_ class => 'browseopts', sub {
                    button_ type => 'submit', name => 'ch', value => ($_//''), ($_//'') eq ($opt->{ch}//'') ? (class => 'optselected') : (), !defined $_ ? 'ALL' : $_ ? uc $_ : '#'
                        for (undef, 'a'..'z', 0);
                };
                input_ type => 'hidden', name => 'ch', value => $opt->{ch}//'';
                $opt->{f}->widget_($count, $time);
            };
        };
        listing_ $opt, $list, $count if $count;
    };
};

1;
