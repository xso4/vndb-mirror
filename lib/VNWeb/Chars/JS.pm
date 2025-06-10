package VNWeb::Chars::JS;

use VNWeb::Prelude;

js_api Chars => { search => { searchquery => 1 } }, sub {
    my $q = shift->{search};

    my $l = $q ? fu->SQL(
        'SELECT c.id, c.title[2] AS title, c.title[4] AS alttitle, c.main, cm.title[2] AS main_title, cm.title[4] AS main_alttitle
           FROM', CHARST, 'c', $q->JOIN('c', 'c.id'), '
           LEFT JOIN', CHARST, 'cm ON cm.id = c.main
          WHERE NOT c.hidden
          ORDER BY sc.score DESC, c.sorttitle
          LIMIT 15
    ')->allh : [];
    for (@$l) {
        $_->{main} = { id => $_->{main}, title => $_->{main_title}, alttitle => $_->{main_alttitle} } if $_->{main};
        delete $_->{main_title};
        delete $_->{main_alttitle};
    }
    +{ results => $l };
};

1;
