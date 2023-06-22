package VNWeb::Misc::AdvSearch;

use VNWeb::Prelude;
use VNWeb::AdvSearch;


elm_api 'AdvSearchSave' => undef, {
    name  => { required => 0, default => '', length => [1,50] },
    qtype => { enum => \%VNWeb::AdvSearch::FIELDS },
    query => {},
}, sub {
    my($d) = @_;
    my $q = tuwf->compile({ advsearch => $d->{qtype} })->validate($d->{query})->data->query_encode;
    tuwf->dbExeci(
        'INSERT INTO saved_queries', { uid => auth->uid, qtype => $d->{qtype}, name => $d->{name}, query => $q },
        'ON CONFLICT (uid, qtype, name) DO UPDATE SET query =', \$q
    );
    elm_Success
};


elm_api 'AdvSearchDel' => undef, {
    name  => { type => 'array', minlength => 1, values => { required => 0, default => '', length => [1,50] } },
    qtype => { enum => \%VNWeb::AdvSearch::FIELDS },
}, sub {
    my($d) = @_;
    tuwf->dbExeci('DELETE FROM saved_queries WHERE uid =', \auth->uid, 'AND qtype =', \$d->{qtype}, 'AND name IN', $d->{name});
    elm_Success
};

1;
