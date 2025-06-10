package VNWeb::Staff::List;

use VNWeb::Prelude;
use VNWeb::AdvSearch;
use VNWeb::Filters;


sub listing_($opt, $list, $count) {
    my sub url { '?'.query_encode({%$opt, @_}) }
    paginate_ \&url, $opt->{p}, [$count, 150], 't';
    article_ class => 'staffbrowse', sub {
        h1_ 'Staff list';
        ul_ sub {
            li_ sub {
                abbr_ class => "icon-lang-$_->{lang}", title => $LANGUAGE{$_->{lang}}{txt}, '';
                a_ href => "/$_->{id}", tattr $_;
            } for @$list;
        };
    };
    paginate_ \&url, $opt->{p}, [$count, 150], 'b';
}


FU::get qr{/s(?:/(?<char>all|[a-z0]))?}, sub($char=undef) {
    my $opt = fu->query(
        q => { searchquery => 1 },
        p => { upage => 1 },
        f => { advsearch_err => 's' },
        n => { accept_array => 'first', default => false, func => sub { $_[0] = !!$_[0]; 1 } },
        ch=> { accept_array => 'first', onerror => undef, enum => ['0', 'a'..'z'] },
        fil => { onerror => undef },
    );

    # compat with old URLs
    $opt->{ch} //= $char if defined $char && $char ne 'all';

    # URL compatibility with old filters
    if(!$opt->{f}->{query} && $opt->{fil}) {
        my $q = eval {
            my $f = filter_parse s => $opt->{fil};
            $opt->{n} = $f->{truename} if defined $f->{truename};
            $f = filter_staff_adv $f;
            FU::Validate->compile({ advsearch => 's' })->validate(@$f > 1 ? $f : undef);
        };
        return fu->redirect(perm => fu->path.'?'.query_encode({%$opt, fil => undef, f => $q})) if $q;
    }

    $opt->{f} = advsearch_default 's' if !$opt->{f}{query} && !defined fu->query('f');

    my $where = AND
        $opt->{n} ? 's.main = s.aid' : (),
        'NOT s.hidden', $opt->{f}->WHERE,
        defined($opt->{ch}) ? SQL 'match_firstchar(s.sorttitle, ', $opt->{ch}, ')' : ();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = fu->SQL('SELECT count(*) FROM', STAFF_ALIAST, 's WHERE', AND $where, $opt->{q}->WHERE('s', 's.id', 's.aid'))->val;
        $list = $count ? fu->SQL('
            SELECT s.id, s.title, s.lang
              FROM', STAFF_ALIAST, 's', $opt->{q}->JOIN('s', 's.id', 's.aid'), '
             WHERE', $where, '
             ORDER BY', $opt->{q} ? 'sc.score DESC, ' : (), 's.sorttitle, s.aid
             LIMIT 150 OFFSET', 150*($opt->{p}-1)
        )->allh : [];
    } || (($count, $list) = (undef, []));
    $time = time - $time;

    framework_ title => 'Browse staff', sub {
        article_ sub {
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
                $opt->{f}->widget_($count, $time);
            };
        };
        listing_ $opt, $list, $count if $count;
    };
};

1;
