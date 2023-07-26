package VNWeb::Producers::Elm;

use VNWeb::Prelude;

elm_api Producers => undef, {
    search => { type => 'array', values => { searchquery => 1 } },
}, sub {
    my($data) = @_;
    my @q = grep $_, $data->{search}->@*;

    elm_ProducerResult @q ? tuwf->dbPagei({ results => 15, page => 1 },
        'SELECT p.id, p.title[1+1] AS name, p.title[1+1+1+1] AS altname
           FROM', producerst, 'p', VNWeb::Validate::SearchQuery::sql_joina(\@q, 'p', 'p.id'), '
          WHERE NOT p.hidden
          ORDER BY sc.score DESC, p.sorttitle
    ') : [];
};

js_api Producers => {
    search => { type => 'array', values => { searchquery => 1 } },
}, sub {
    my($data) = @_;
    my @q = grep $_, $data->{search}->@*;

    +{ results => @q ? tuwf->dbAlli(
        'SELECT p.id, p.title[1+1] AS name, p.title[1+1+1+1] AS altname
           FROM', producerst, 'p', VNWeb::Validate::SearchQuery::sql_joina(\@q, 'p', 'p.id'), '
          WHERE NOT p.hidden
          ORDER BY sc.score DESC, p.sorttitle
          LIMIT', \30
    ) : [] };
};

1;
