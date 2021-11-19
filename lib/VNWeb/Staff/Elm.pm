package VNWeb::Staff::Elm;

use VNWeb::Prelude;

elm_api Staff => undef, { search => {} }, sub {
    my $q = shift->{search};

    elm_StaffResult tuwf->dbPagei({ results => 15, page => 1 },
        'SELECT s.id, sa.aid, sa.name, sa.original
           FROM (',
			sql_join('UNION ALL',
                $q =~ /^$RE{sid}$/ ? sql('SELECT 0, aid FROM staff_alias WHERE id =', \"$+{id}") : (),
                sql('SELECT 1+substr_score(lower(name),', \sql_like($q), ')+substr_score(lower(original),', \sql_like($q), '), aid
                       FROM staff_alias WHERE c_search LIKE ALL (search_query(', \$q, '))'),
            ), ') x(prio, aid)
           JOIN staff_alias sa ON sa.aid = x.aid
           JOIN staff s ON s.id = sa.id
          WHERE NOT s.hidden
          GROUP BY s.id, sa.aid, sa.name, sa.original
          ORDER BY MIN(x.prio), sa.name
    ');
};

1;
