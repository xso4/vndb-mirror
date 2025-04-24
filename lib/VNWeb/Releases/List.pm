package VNWeb::Releases::List;

use VNWeb::Prelude;
use VNWeb::AdvSearch;
use VNWeb::Filters;
use VNWeb::Releases::Lib;


sub listing_ {
    my($opt, $list, $count) = @_;
    my sub url { '?'.query_encode({%$opt, @_}) }
    paginate_ \&url, $opt->{p}, [$count, 50], 't';
    article_ class => 'browse', sub {
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


FU::get '/r', sub {
    my $opt = fu->query(
        q => { searchquery => 1 },
        p => { upage => 1 },
        f => { advsearch_err => 'r' },
        s => { onerror => 'qscore', enum => [qw/qscore released minage title/] },
        o => { onerror => 'a', enum => ['a','d'] },
        fil => { onerror => '' },
    );
    $opt->{s} = 'qscore' if $opt->{q} && fu->query('sb');
    $opt->{s} = 'title' if $opt->{s} eq 'qscore' && !$opt->{q};

    # URL compatibility with old filters
    if(!$opt->{f}->{query} && $opt->{fil}) {
        my $q = eval {
            FU::Validate->compile({ advsearch => 'r' })->validate(filter_release_adv filter_parse r => $opt->{fil});
        };
        fu->redirect(perm => fu->path.'?'.query_encode({%$opt, fil => undef, f => $q})) if $q;
    }

    $opt->{f} = advsearch_default 'r' if !$opt->{f}{query} && !defined fu->query('f');

    my $where = sql_and
        'NOT r.hidden',
        'r.official OR EXISTS(SELECT 1 FROM releases_titles rt WHERE rt.id = r.id AND NOT rt.mtl)',
        $opt->{f}->sql_where();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = fu->dbVali('SELECT count(*) FROM releases r WHERE', sql_and $where, $opt->{q}->sql_where('r', 'r.id'));
        $list = $count ? fu->dbPagei({results => 50, page => $opt->{p}}, '
            SELECT r.id, r.patch, r.released
              FROM', releasest, 'r', $opt->{q}->sql_join('r', 'r.id'), '
             WHERE', $where, '
             ORDER BY', sprintf {
                 qscore   => '10 - sc.score %s, r.sorttitle %1$s',
                 title    => 'r.sorttitle %s, r.released %1$s',
                 minage   => 'r.minage %s, r.sorttitle %1$s, r.released %1$s',
                 released => 'r.released %s, r.sorttitle %1$s, r.id %1$s',
             }->{$opt->{s}}, $opt->{o} eq 'a' ? 'ASC' : 'DESC'
        ) : [];
    } || (($count, $list) = (undef, []));

    enrich_vislinks r => 0, $list;
    enrich_release $list;
    $time = time - $time;

    framework_ title => 'Browse releases', sub {
        article_ sub {
            h1_ 'Browse releases';
            form_ action => '/r', method => 'get', sub {
                searchbox_ r => $opt->{q}//'';
                input_ type => 'hidden', name => 'o', value => $opt->{o};
                input_ type => 'hidden', name => 's', value => $opt->{s};
                $opt->{f}->widget_($count, $time);
            };
        };
        listing_ $opt, $list, $count if $count;
    };
};

1;
