package VNWeb::Staff::JS;

use VNWeb::Prelude;

js_api Staff => {
    search => { elems => { searchquery => 1 } },
}, sub($data) {
    my @q = grep $_, $data->{search}->@*;
    +{ results => @q ? fu->SQL(
        'SELECT s.id AS sid, s.lang, s.aid AS id, s.title[2], s.title[4] as alttitle
           FROM', STAFF_ALIAST, 's', VNWeb::Validate::SearchQuery::JOINA(\@q, 's', 's.id', 's.aid'), '
          WHERE NOT s.hidden
          ORDER BY sc.score DESC, s.sorttitle
          LIMIT 30'
    )->allh : [] };
};

1;
