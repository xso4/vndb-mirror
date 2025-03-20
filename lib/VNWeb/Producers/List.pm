package VNWeb::Producers::List;

use VNWeb::Prelude;
use VNWeb::AdvSearch;


sub listing_ {
    my($opt, $list, $count) = @_;

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


TUWF::get qr{/p(?:/(?<char>all|[a-z0]))?}, sub {
    my $char = tuwf->capture('char');
    my $opt = tuwf->validate(get =>
        p => { upage => 1 },
        q => { searchquery => 1 },
        f => { advsearch_err => 'p' },
        ch=> { onerror => [], type => 'array', scalar => 1, values => { onerror => undef, enum => ['0', 'a'..'z'] } },
    )->data;
    $opt->{ch} = $opt->{ch}[0];

    # compat with old URLs
    my $oldch = tuwf->capture('char');
    $opt->{ch} //= $oldch if defined $oldch && $oldch ne 'all';

    $opt->{f} = advsearch_default 'p' if !$opt->{f}{query} && !defined tuwf->reqGet('f');

    my $where = sql_and 'NOT p.hidden', $opt->{f}->sql_where(),
        defined($opt->{ch}) ? sql 'match_firstchar(p.sorttitle, ', \$opt->{ch}, ')' : ();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = tuwf->dbVali('SELECT COUNT(*) FROM', producerst, 'p WHERE', sql_and $where, $opt->{q}->sql_where('p', 'p.id'));
        $list = $count ? tuwf->dbPagei({ results => 150, page => $opt->{p} },
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
                $opt->{f}->elm_($count, $time);
            };
        };
        listing_ $opt, $list, $count if $count;
    };
};

1;
