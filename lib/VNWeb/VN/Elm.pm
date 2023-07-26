package VNWeb::VN::Elm;

use VNWeb::Prelude;

elm_api VN => undef, {
    search => { type => 'array', values => { searchquery => 1 } },
    hidden => { anybool => 1 },
}, sub {
    my($data) = @_;
    my @q = grep $_, $data->{search}->@*;

    elm_VNResult @q ? tuwf->dbPagei({ results => $data->{hidden}?50:15, page => 1 },
        'SELECT v.id, v.title[1+1] AS title, v.hidden
           FROM', vnt, 'v', VNWeb::Validate::SearchQuery::sql_joina(\@q, 'v', 'v.id'),
          $data->{hidden} ? () : 'WHERE NOT v.hidden', '
          ORDER BY sc.score DESC, v.sorttitle
    ') : [];
};


js_api VN => {
    search => { type => 'array', values => { searchquery => 1 } },
    hidden => { anybool => 1 },
}, sub {
    my($data) = @_;
    my @q = grep $_, $data->{search}->@*;

    +{ results => @q ? tuwf->dbAlli(
         'SELECT v.id, v.title[1+1] AS title, v.hidden
           FROM', vnt, 'v', VNWeb::Validate::SearchQuery::sql_joina(\@q, 'v', 'v.id'),
          $data->{hidden} ? () : 'WHERE NOT v.hidden', '
          ORDER BY sc.score DESC, v.sorttitle
          LIMIT', \50
    ) : [] };
};

1;
