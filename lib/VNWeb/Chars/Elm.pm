package VNWeb::Chars::Elm;

use VNWeb::Prelude;

elm_api Chars => undef, { search => {} }, sub {
    my $q = shift->{search};

    my $l = tuwf->dbPagei({ results => 15, page => 1 },
        'SELECT c.id, c.name, c.original, c.main, cm.name AS main_name, cm.original AS main_original
           FROM (SELECT MIN(prio), id FROM (',
			sql_join('UNION ALL',
                $q =~ /^$RE{cid}$/ ? sql('SELECT 1, id FROM chars WHERE id =', \"$+{id}") : (),
                sql('SELECT  1+substr_score(lower(name),', \sql_like($q),'), id FROM chars WHERE c_search LIKE ALL (search_query(', \$q, '))'),
            ), ') x(prio,id) GROUP BY id) x(prio, id)
           JOIN chars c ON c.id = x.id
           LEFT JOIN chars cm ON cm.id = c.main
          WHERE NOT c.hidden
          ORDER BY x.prio, c.name
    ');
    for (@$l) {
        $_->{main} = { id => $_->{main}, name => $_->{main_name}, original => $_->{main_original} } if $_->{main};
        delete $_->{main_name};
        delete $_->{main_original};
    }
    elm_CharResult $l;
};

1;
