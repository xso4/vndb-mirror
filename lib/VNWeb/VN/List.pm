package VNWeb::VN::List;

use VNWeb::Prelude;
use VNWeb::AdvSearch;


TUWF::get qr{/experimental/v}, sub {
    my $opt = tuwf->validate(get =>
        q => { onerror => '' },
        p => { upage => 1 },
        f => { advsearch => 'v' },
    )->data;

    my $where = sql_and
        'NOT v.hidden',
        $opt->{q} ? map sql('v.c_search LIKE', \"%$_%"), normalize_query $opt->{q} : (),
        $opt->{f} ? as_tosql(v => $opt->{f}) : ();

    my $time = time;
    my $count = tuwf->dbVali('SELECT count(*) FROM vn v WHERE', $where);
    $time = time - $time;

    framework_ title => 'Browse visual novels', sub {
        div_ class => 'mainbox', sub {
            h1_ 'Browse visual novels';
            div_ class => 'warning', sub {
                h2_ 'EXPERIMENTAL';
                p_ "This is Yorhel's playground. Lots of functionality is missing, lots of stuff is or will be broken. Here be dragons. Etc.";
            };
            br_;
            form_ action => '/experimental/v', method => 'get', sub {
                searchbox_ v => $opt->{q};
                as_elm_ v => $opt->{f};
            };
            p_ sprintf '%d results in %.3fs', $count, $time;
        };
    };
};

1;
