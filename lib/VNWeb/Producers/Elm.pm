package VNWeb::Producers::Elm;

use VNWeb::Prelude;

elm_api Producers => undef, {
    search => { type => 'array', values => { required => 0, default => '' } },
    hidden => { anybool => 1 },
}, sub {
    my($data) = @_;
    my @q = grep length $_, $data->{search}->@*;
    die "No query" if !@q;

    elm_ProducerResult tuwf->dbPagei({ results => 15, page => 1 },
        'SELECT p.id, p.name, p.original, p.hidden
           FROM (',
			sql_join('UNION ALL', map +(
                /^$RE{pid}$/ ? sql('SELECT 1, id FROM producers WHERE id =', \"$+{id}") : (),
                sql('SELECT 1+substr_score(lower(name),', \sql_like($_), '), id FROM producers WHERE c_search LIKE ALL (search_query(', \"$_", '))'),
            ), @q),
            ') x(prio, id)
           JOIN producers p ON p.id = x.id
          WHERE', sql_and($data->{hidden} ? () : 'NOT p.hidden'), '
          GROUP BY p.id, p.name, p.original, p.hidden
          ORDER BY MIN(x.prio), p.name
    ');
};

1;
