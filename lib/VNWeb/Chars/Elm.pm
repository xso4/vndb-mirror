package VNWeb::Chars::Elm;

use VNWeb::Prelude;

elm_api Chars => undef, { search => {} }, sub {
    my $q = shift->{search};

    my $l = tuwf->dbPagei({ results => 15, page => 1 },
        'SELECT c.id, c.title[1+1] AS title, c.title[1+1+1+1] AS alttitle, c.main, cm.title[1+1] AS main_title, cm.title[1+1+1+1] AS main_alttitle
           FROM (SELECT MIN(prio), id FROM (',
			sql_join('UNION ALL',
                $q =~ /^$RE{cid}$/ ? sql('SELECT 1, id FROM chars WHERE id =', \"$+{id}") : (),
                sql('SELECT  1+substr_score(lower(name),', \sql_like($q),'), id FROM chars WHERE c_search LIKE ALL (search_query(', \$q, '))'),
            ), ') x(prio,id) GROUP BY id) x(prio, id)
           JOIN', charst, 'c ON c.id = x.id
           LEFT JOIN', charst, 'cm ON cm.id = c.main
          WHERE NOT c.hidden
          ORDER BY x.prio, c.title[1+1]
    ');
    for (@$l) {
        $_->{main} = { id => $_->{main}, title => $_->{main_title}, alttitle => $_->{main_alttitle} } if $_->{main};
        delete $_->{main_title};
        delete $_->{main_alttitle};
    }
    elm_CharResult $l;
};

1;
