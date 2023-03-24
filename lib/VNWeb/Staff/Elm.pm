package VNWeb::Staff::Elm;

use VNWeb::Prelude;

elm_api Staff => undef, {
    search => { type => 'array', values => { searchquery => 1 } },
}, sub {
    my($data) = @_;
    my @q = grep $_, $data->{search}->@*;
    die "No query" if !@q;

    elm_StaffResult tuwf->dbPagei({ results => 15, page => 1 },
        'SELECT s.id, s.lang, s.aid, s.title[1+1], s.title[1+1+1+1] as alttitle
           FROM', staff_aliast, 's', VNWeb::Validate::SearchQuery::sql_joina(\@q, 's', 's.id', 's.aid'), '
          WHERE NOT s.hidden
          ORDER BY sc.score DESC, s.sorttitle
    ');
};

1;
