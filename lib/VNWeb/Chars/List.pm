package VNWeb::Chars::List;

use VNWeb::Prelude;
use VNWeb::AdvSearch;
use VNWeb::Filters;


# Also used by VNWeb::TT::TraitPage
sub listing_ {
    my($opt, $list, $count) = @_;
    my sub url { '?'.query_encode %$opt, @_ }
    paginate_ \&url, $opt->{p}, [$count, 50], 't';
    div_ class => 'mainbox browse charb', sub {
        table_ class => 'stripe', sub {
            tr_ sub {
                td_ class => 'tc1', sub {
                    abbr_ class => "icons gen $_->{gender}", title => $GENDER{$_->{gender}}, '' if $_->{gender} ne 'unknown';
                };
                td_ class => 'tc2', sub {
                    a_ href => "/c$_->{id}", title => $_->{original}||$_->{name}, $_->{name};
                    b_ class => 'grayedout', sub {
                        join_ ', ', sub { a_ href => "/v$_->{id}", title => $_->{original}||$_->{title}, $_->{title} }, $_->{vn}->@*;
                    };
                };
            } for @$list;
        }
    };
    paginate_ \&url, $opt->{p}, [$count, 50], 'b';
}


# Also used by VNWeb::TT::TraitPage
sub enrich_listing {
    enrich vn => id => cid => sub { sql '
        SELECT cv.id AS cid, v.id, v.title, v.original
          FROM chars_vns cv
          JOIN vn v ON v.id = cv.vid
         WHERE NOT v.hidden AND cv.id IN', $_, '
         ORDER BY v.title'
    }, @_;
}


TUWF::get qr{/c(?:/(?<char>all|[a-z0]))?}, sub {
    my $opt = tuwf->validate(get =>
        q => { onerror => undef },
        p => { upage => 1 },
        f => { advsearch_err => 'c' },
        ch=> { onerror => [], type => 'array', scalar => 1, values => { onerror => undef, enum => ['0', 'a'..'z'] } },
        fil => { required => 0 },
    )->data;
    $opt->{ch} = $opt->{ch}[0];

    # compat with old URLs
    my $oldch = tuwf->capture('char');
    $opt->{ch} //= $oldch if defined $oldch && $oldch ne 'all';

    # URL compatibility with old filters
    if(!$opt->{f}->{query} && $opt->{fil}) {
        my $q = eval {
            my $f = filter_char_adv filter_parse c => $opt->{fil};
            tuwf->compile({ advsearch => 'c' })->validate(@$f > 1 ? $f : undef)->data;
        };
        if(!$q) {
            warn "Filter compatibility conversion failed\n$@";
        } else {
            return tuwf->resRedirect(tuwf->reqPath().'?'.query_encode(%$opt, fil => undef, f => $q), 'temp');
        }
    }

    $opt->{f} = advsearch_default 'c' if !$opt->{f}{query} && !defined tuwf->reqGet('f');

    my @search = map {
        my $l = '%'.sql_like($_).'%';
        length $_ > 0 ? sql '(c.name ILIKE', \$l, "OR translate(c.original,' ','') ILIKE", \$l, "OR translate(c.alias,' ','') ILIKE", \$l, ')' : ();
    } split /[ -,._]/, $opt->{q}||'';

    my $where = sql_and
        'NOT c.hidden', $opt->{f}->sql_where(), @search,
        defined($opt->{ch}) && $opt->{ch} ? sql('LOWER(SUBSTR(c.name, 1, 1)) =', \$opt->{ch}) : (),
        defined($opt->{ch}) && !$opt->{ch} ? sql('(ASCII(c.name) <', \97, 'OR ASCII(c.name) >', \122, ') AND (ASCII(c.name) <', \65, 'OR ASCII(c.name) >', \90, ')') : ();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = tuwf->dbVali('SELECT count(*) FROM chars c WHERE', $where);
        $list = $count ? tuwf->dbPagei({results => 50, page => $opt->{p}}, '
            SELECT c.id, c.name, c.original, c.gender FROM chars c WHERE', $where, 'ORDER BY c.name, c.id'
        ) : [];
    } || (($count, $list) = (undef, []));

    enrich_listing $list;
    $time = time - $time;

    framework_ title => 'Browse characters', sub {
        div_ class => 'mainbox', sub {
            h1_ 'Browse characters';
            form_ action => '/c', method => 'get', sub {
                searchbox_ c => $opt->{q}//'';
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
