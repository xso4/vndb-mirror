package VNWeb::Staff::JS;

use VNWeb::Prelude;

js_api Staff => {
    search => { elems => { searchquery => 1 } },
}, sub {
    my($data) = @_;
    my @q = grep $_, $data->{search}->@*;

    +{ results => @q ? tuwf->dbAlli(
        'SELECT s.id AS sid, s.lang, s.aid AS id, s.title[1+1], s.title[1+1+1+1] as alttitle
           FROM', staff_aliast, 's', VNWeb::Validate::SearchQuery::sql_joina(\@q, 's', 's.id', 's.aid'), '
          WHERE NOT s.hidden
          ORDER BY sc.score DESC, s.sorttitle
          LIMIT', \30
    ) : [] };
};

1;
