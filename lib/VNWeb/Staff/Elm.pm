package VNWeb::Staff::Elm;

use VNWeb::Prelude;

elm_api Staff => undef, { search => { searchquerya => 1 } }, sub {
    my $q = shift->{search};
    die "No query" if !$q;

    elm_StaffResult tuwf->dbPagei({ results => 15, page => 1 },
        'SELECT s.id, s.lang, s.aid, s.title[1+1], s.title[1+1+1+1] as alttitle
           FROM', staff_aliast, 's', $q->sql_join('s', 's.id', 's.aid'), '
          WHERE NOT s.hidden
          ORDER BY sc.score DESC, s.sorttitle
    ');
};

1;
