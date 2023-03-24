package VNWeb::VN::Elm;

use VNWeb::Prelude;

elm_api VN => undef, {
    search => { type => 'array', values => { searchquery => 1 } },
    hidden => { anybool => 1 },
}, sub {
    my($data) = @_;
    my @q = grep $_, $data->{search}->@*;
    die "No query" if !@q;

    elm_VNResult tuwf->dbPagei({ results => $data->{hidden}?50:15, page => 1 },
        'SELECT v.id, v.title[1+1] AS title, v.hidden
           FROM', vnt, 'v', VNWeb::Validate::SearchQuery::sql_joina(\@q, 'v', 'v.id'),
          $data->{hidden} ? () : 'WHERE NOT v.hidden', '
          ORDER BY sc.score DESC, v.sorttitle
    ');
};

1;
