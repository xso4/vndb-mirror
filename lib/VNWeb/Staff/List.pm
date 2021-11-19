package VNWeb::Staff::List;

use VNWeb::Prelude;
use VNWeb::AdvSearch;
use VNWeb::Filters;


sub listing_ {
    my($opt, $list, $count) = @_;
    my sub url { '?'.query_encode %$opt, @_ }
    paginate_ \&url, $opt->{p}, [$count, 150], 't';
    div_ class => 'mainbox staffbrowse', sub {
        h1_ 'Staff list';
        ul_ sub {
            li_ sub {
                abbr_ class => "icons lang $_->{lang}", title => $LANGUAGE{$_->{lang}}, '';
                a_ href => "/$_->{id}", title => $_->{original}||$_->{name}, $_->{name};
            } for @$list;
        };
    };
    paginate_ \&url, $opt->{p}, [$count, 150], 'b';
}


TUWF::get qr{/s(?:/(?<char>all|[a-z0]))?}, sub {
    my $opt = tuwf->validate(get =>
        q => { onerror => undef },
        p => { upage => 1 },
        f => { advsearch_err => 's' },
        n => { onerror => [], type => 'array', scalar => 1, values => { anybool => 1 } },
        ch=> { onerror => [], type => 'array', scalar => 1, values => { onerror => undef, enum => ['0', 'a'..'z'] } },
        fil => { required => 0 },
    )->data;
    $opt->{ch} = $opt->{ch}[0];
    $opt->{n} = $opt->{n}[0];

    # compat with old URLs
    my $oldch = tuwf->capture('char');
    $opt->{ch} //= $oldch if defined $oldch && $oldch ne 'all';

    # URL compatibility with old filters
    if(!$opt->{f}->{query} && $opt->{fil}) {
        my $q = eval {
            my $f = filter_parse s => $opt->{fil};
            $opt->{n} = $f->{truename} if defined $f->{truename};
            $f = filter_staff_adv $f;
            tuwf->compile({ advsearch => 's' })->validate(@$f > 1 ? $f : undef)->data;
        };
        return tuwf->resRedirect(tuwf->reqPath().'?'.query_encode(%$opt, fil => undef, f => $q), 'perm') if $q;
    }

    $opt->{f} = advsearch_default 's' if !$opt->{f}{query} && !defined tuwf->reqGet('f');

    my $where = sql_and
        $opt->{n} ? 's.aid = sa.aid' : (),
        'NOT s.hidden', $opt->{f}->sql_where(),
        $opt->{q} ? sql 'sa.c_search LIKE ALL (search_query(', \$opt->{q}, '))' : (),
        defined($opt->{ch}) && $opt->{ch} ? sql('LOWER(SUBSTR(sa.name, 1, 1)) =', \$opt->{ch}) : (),
        defined($opt->{ch}) && !$opt->{ch} ? sql('(ASCII(sa.name) <', \97, 'OR ASCII(sa.name) >', \122, ') AND (ASCII(sa.name) <', \65, 'OR ASCII(sa.name) >', \90, ')') : ();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = tuwf->dbVali('SELECT count(*) FROM staff s JOIN staff_alias sa ON sa.id = s.id WHERE', $where);
        $list = $count ? tuwf->dbPagei({results => 150, page => $opt->{p}}, '
            SELECT s.id, sa.name, sa.original, s.lang FROM staff s JOIN staff_alias sa ON sa.id = s.id WHERE', $where, 'ORDER BY sa.name, sa.aid'
        ) : [];
    } || (($count, $list) = (undef, []));
    $time = time - $time;

    framework_ title => 'Browse staff', sub {
        div_ class => 'mainbox', sub {
            h1_ 'Browse staff';
            form_ action => '/s', method => 'get', sub {
                searchbox_ s => $opt->{q}//'';
                p_ class => 'browseopts', sub {
                    button_ type => 'submit', name => 'ch', value => ($_//''), ($_//'') eq ($opt->{ch}//'') ? (class => 'optselected') : (), !defined $_ ? 'ALL' : $_ ? uc $_ : '#'
                        for (undef, 'a'..'z', 0);
                };
                p_ class => 'browseopts', sub {
                    button_ type => 'submit', name => 'n', value => 0, !$opt->{n} ? (class => 'optselected') : (), 'Display aliases';
                    button_ type => 'submit', name => 'n', value => 1, $opt->{n}  ? (class => 'optselected') : (), 'Hide aliases';
                };
                input_ type => 'hidden', name => 'ch', value => $opt->{ch}//'';
                input_ type => 'hidden', name => 'n', value => $opt->{n}//0;
                $opt->{f}->elm_;
                advsearch_msg_ $count, $time;
            };
        };
        listing_ $opt, $list, $count if $count;
    };
};

1;
