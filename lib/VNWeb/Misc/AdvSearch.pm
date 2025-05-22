package VNWeb::Misc::AdvSearch;

use VNWeb::Prelude;
use VNWeb::AdvSearch;


js_api AdvSearchSave => {
    name  => { default => '', length => [1,50] },
    qtype => { enum => \%VNWeb::AdvSearch::FIELDS },
    query => {},
}, sub($d) {
    fu->denied if !auth;
    my $q = FU::Validate->compile({ advsearch => $d->{qtype} })->validate($d->{query})->enc_query;
    fu->SQL(
        'INSERT INTO saved_queries', VALUES({ uid => auth->uid, qtype => $d->{qtype}, name => $d->{name}, query => $q }),
        'ON CONFLICT (uid, qtype, name) DO UPDATE SET query =', $q
    )->exec;
    +{}
};


js_api AdvSearchDel => {
    name  => { minlength => 1, elems => { default => '', length => [1,50] } },
    qtype => { enum => \%VNWeb::AdvSearch::FIELDS },
}, sub($d) {
    fu->denied if !auth;
    fu->SQL('DELETE FROM saved_queries WHERE uid =', auth->uid, 'AND qtype =', $d->{qtype}, 'AND name', IN $d->{name})->exec;
    +{}
};

1;
