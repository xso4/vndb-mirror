package VNWeb::Chars::JS;

use VNWeb::Prelude;

js_api Chars => { search => { searchquery => 1 } }, sub {
    my $q = shift->{search};

    my $l = $q ? fu->dbPagei({ results => 15, page => 1 },
        'SELECT c.id, c.title[1+1] AS title, c.title[1+1+1+1] AS alttitle, c.main, cm.title[1+1] AS main_title, cm.title[1+1+1+1] AS main_alttitle
           FROM', charst, 'c', $q->sql_join('c', 'c.id'), '
           LEFT JOIN', charst, 'cm ON cm.id = c.main
          WHERE NOT c.hidden
          ORDER BY sc.score DESC, c.sorttitle
    ') : [];
    for (@$l) {
        $_->{main} = { id => $_->{main}, title => $_->{main_title}, alttitle => $_->{main_alttitle} } if $_->{main};
        delete $_->{main_title};
        delete $_->{main_alttitle};
    }
    +{ results => $l };
};

1;
