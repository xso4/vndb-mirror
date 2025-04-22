package VNWeb::Producers::JS;

use VNWeb::Prelude;

js_api Producers => {
    search => { elems => { searchquery => 1 } },
}, sub {
    my($data) = @_;
    my @q = grep $_, $data->{search}->@*;

    +{ results => @q ? fu->dbAlli(
        'SELECT p.id, p.title[1+1] AS name, p.title[1+1+1+1] AS altname
           FROM', producerst, 'p', VNWeb::Validate::SearchQuery::sql_joina(\@q, 'p', 'p.id'), '
          WHERE NOT p.hidden
          ORDER BY sc.score DESC, p.sorttitle
          LIMIT', \30
    ) : [] };
};

1;
