package VNWeb::Staff::Elm;

use VNWeb::Prelude;

elm_api Staff => undef, {
    search => { type => 'array', values => { required => 0, default => '' } },
}, sub {
    my @q = grep length $_, shift->{search}->@*;
    die "No query" if !@q;

    elm_StaffResult tuwf->dbPagei({ results => 15, page => 1 },
        'SELECT s.id, s.lang, s.aid, s.title[1+1], s.title[1+1+1+1] as alttitle
           FROM (',
			sql_join('UNION ALL', map +(
                /^$RE{sid}$/ ? sql('SELECT 0, aid FROM staff_alias WHERE id =', \"$+{id}") : (),
                sql('SELECT 1+substr_score(lower(name),', \sql_like($_), ')+substr_score(lower(original),', \sql_like($_), '), aid
                       FROM staff_alias WHERE c_search LIKE ALL (search_query(', \$_, '))'),
            ), @q),
            ') x(prio, aid)
           JOIN', staff_aliast, 's ON s.aid = x.aid
          WHERE NOT s.hidden
          GROUP BY s.id, s.lang, s.aid, s.title, s.sorttitle
          ORDER BY MIN(x.prio), s.sorttitle
    ');
};

1;
