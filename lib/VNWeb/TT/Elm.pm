package VNWeb::TT::Elm;

use VNWeb::Prelude;

elm_api Tags => undef, { search => { searchquery => 1 } }, sub {
    my $q = shift->{search};

    elm_TagResult $q ? tuwf->dbPagei({ results => 15, page => 1 },
        'SELECT t.id, t.name, t.searchable, t.applicable, t.hidden, t.locked
           FROM tags t', $q->sql_join('g', 't.id'), '
          WHERE NOT (t.hidden AND t.locked)
          ORDER BY sc.score DESC, t.name
    ') : [];
};


js_api Tags => { search => { searchquery => 1 } }, sub {
    my $q = shift->{search};

    +{ results => $q ? tuwf->dbAlli(
        'SELECT t.id, t.name, t.searchable, t.applicable, t.hidden, t.locked
           FROM tags t', $q->sql_join('g', 't.id'), '
          WHERE NOT (t.hidden AND t.locked)
          ORDER BY sc.score DESC, t.name
          LIMIT', \15
    ) : [] }
};


elm_api Traits => undef, { search => { searchquery => 1 } }, sub {
    my $q = shift->{search};

    elm_TraitResult $q ? tuwf->dbPagei({ results => 15, page => 1 },
        'SELECT t.id, t.name, t.searchable, t.applicable, t.defaultspoil, t.hidden, t.locked, g.id AS group_id, g.name AS group_name
           FROM traits t', $q->sql_join('i', 't.id'), '
           LEFT JOIN traits g ON g.id = t.gid
          WHERE NOT (t.hidden AND t.locked)
          ORDER BY sc.score DESC, t.name
    ') : [];
};

1;
