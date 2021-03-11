package VNWeb::TT::Elm;

use VNWeb::Prelude;

elm_api Tags => undef, { search => {} }, sub {
    my $q = shift->{search};
    my $qs = sql_like $q;

    elm_TagResult tuwf->dbPagei({ results => 15, page => 1 },
        'SELECT t.id, t.name, t.searchable, t.applicable, t.hidden, t.locked
           FROM (',
             sql_join('UNION ALL',
                 $q =~ /^$RE{gid}$/ ? sql('SELECT 1, id FROM tags WHERE id =', \"$+{id}") : (),
                 sql('SELECT  1+substr_score(lower(name),',  \$qs, '), id FROM tags WHERE name  ILIKE', \"%$qs%"),
                 sql('SELECT 10+substr_score(lower(alias),', \$qs, '), id FROM tags WHERE alias ILIKE', \"%$qs%"),
             ), ') x (prio, id)
           JOIN tags t ON t.id = x.id
          WHERE NOT (t.hidden AND t.locked)
          GROUP BY t.id, t.name, t.searchable, t.applicable, t.hidden, t.locked
          ORDER BY MIN(x.prio), t.name
    ')
};


elm_api Traits => undef, { search => {} }, sub {
    my $q = shift->{search};
    my $qs = sql_like $q;

    elm_TraitResult tuwf->dbPagei({ results => 15, page => 1 },
        'SELECT t.id, t.name, t.searchable, t.applicable, t.defaultspoil, t.state, g.id AS group_id, g.name AS group_name
           FROM (SELECT MIN(prio), id FROM (',
             sql_join('UNION ALL',
                 $q =~ /^$RE{iid}$/ ? sql('SELECT 1, id FROM traits WHERE id =', \"$+{id}") : (),
                 sql('SELECT  1+substr_score(lower(name),',  \$qs, '), id FROM traits WHERE name  ILIKE', \"%$qs%"),
                 sql('SELECT 10+substr_score(lower(alias),', \$qs, '), id FROM traits WHERE alias ILIKE', \"%$qs%"),
             ), ') x(prio, id) GROUP BY id) x(prio,id)
           JOIN traits t ON t.id = x.id
           LEFT JOIN traits g ON g.id = t.group
          WHERE t.state <> 1
          ORDER BY x.prio, t.name
    ')
};

1;
