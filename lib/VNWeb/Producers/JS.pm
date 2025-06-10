package VNWeb::Producers::JS;

use VNWeb::Prelude;

js_api Producers => {
    search => { elems => { searchquery => 1 } },
}, sub($data) {
    my @q = grep $_, $data->{search}->@*;
    +{ results => @q ? fu->SQL(
        'SELECT p.id, p.title[2] AS name, p.title[4] AS altname
           FROM', PRODUCERST, 'p', VNWeb::Validate::SearchQuery::JOINA(\@q, 'p', 'p.id'), '
          WHERE NOT p.hidden
          ORDER BY sc.score DESC, p.sorttitle
          LIMIT 30'
    )->allh : [] };
};

1;
