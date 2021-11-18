package VNWeb::Releases::List;

use VNDB::Func 'gtintype';
use VNWeb::Prelude;
use VNWeb::AdvSearch;
use VNWeb::Filters;
use VNWeb::Releases::Lib;


sub listing_ {
    my($opt, $list, $count) = @_;
    my sub url { '?'.query_encode %$opt, @_ }
    paginate_ \&url, $opt->{p}, [$count, 50], 't';
    div_ class => 'mainbox browse', sub {
        table_ class => 'stripe releases', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub { txt_ 'Date';   sortable_ 'released',$opt, \&url; debug_ $list; };
                td_ class => 'tc2', sub { txt_ 'Rating'; sortable_ 'minage',  $opt, \&url };
                td_ class => 'tc3', '';
                td_ class => 'tc4', sub { txt_ 'Title';  sortable_ 'title',   $opt, \&url };
                td_ class => 'tc_icons', '';
                td_ class => 'tc5', '';
                td_ class => 'tc6', '';
            } };
            my $ropt = { id => '' };
            release_row_ $_, $ropt for @$list;
        }
    };
    paginate_ \&url, $opt->{p}, [$count, 50], 'b';
}


TUWF::get qr{/r}, sub {
    my $opt = tuwf->validate(get =>
        q => { onerror => undef },
        p => { upage => 1 },
        f => { advsearch_err => 'r' },
        s => { onerror => 'title', enum => [qw/released minage title/] },
        o => { onerror => 'a', enum => ['a','d'] },
        fil => { required => 0 },
    )->data;

    # URL compatibility with old filters
    if(!$opt->{f}->{query} && $opt->{fil}) {
        my $q = eval {
            tuwf->compile({ advsearch => 'r' })->validate(filter_release_adv filter_parse r => $opt->{fil})->data;
        };
        return tuwf->resRedirect(tuwf->reqPath().'?'.query_encode(%$opt, fil => undef, f => $q), 'perm') if $q;
    }

    $opt->{f} = advsearch_default 'r' if !$opt->{f}{query} && !defined tuwf->reqGet('f');

    my $where = sql_and 'NOT r.hidden', $opt->{f}->sql_where(),
        !$opt->{q} ? () : sql_or
            sql('r.c_search LIKE ALL (search_query(', \$opt->{q}, '))'),
            $opt->{q} =~ /^\d+$/ && gtintype($opt->{q}) ? sql 'r.gtin =', \$opt->{q} : (),
            $opt->{q} =~ /^[a-zA-Z0-9-]+$/ ? sql 'r.catalog =', \$opt->{q} : ();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = tuwf->dbVali('SELECT count(*) FROM releases r WHERE', $where);
        $list = $count ? tuwf->dbPagei({results => 50, page => $opt->{p}}, '
            SELECT r.id, r.patch, r.released, r.gtin, ', sql_extlinks(r => 'r.'), '
              FROM releases r
             WHERE', $where, '
             ORDER BY', sprintf {
                 title    => 'r.title %s, r.released %1$s',
                 minage   => 'r.minage %s, r.title %1$s, r.released %1$s',
                 released => 'r.released %s, r.id %1$s',
             }->{$opt->{s}}, $opt->{o} eq 'a' ? 'ASC' : 'DESC'
        ) : [];
    } || (($count, $list) = (undef, []));

    enrich_extlinks r => $list;
    enrich_release $list;
    $time = time - $time;

    framework_ title => 'Browse releases', sub {
        div_ class => 'mainbox', sub {
            h1_ 'Browse releases';
            form_ action => '/r', method => 'get', sub {
                searchbox_ r => $opt->{q}//'';
                input_ type => 'hidden', name => 'o', value => $opt->{o};
                input_ type => 'hidden', name => 's', value => $opt->{s};
                $opt->{f}->elm_;
                advsearch_msg_ $count, $time;
            };
        };
        listing_ $opt, $list, $count if $count;
    };
};

1;
