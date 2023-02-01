package VNWeb::VN::Elm;

use VNWeb::Prelude;

elm_api VN => undef, {
    search => { type => 'array', values => { required => 0, default => '' } },
    hidden => { anybool => 1 },
}, sub {
    my($data) = @_;
    my @q = grep length $_, $data->{search}->@*;
    die "No query" if !@q;

    elm_VNResult tuwf->dbPagei({ results => $data->{hidden}?50:15, page => 1 },
        'SELECT v.id, v.title, v.alttitle, v.hidden
           FROM (',
            sql_join('UNION ALL', map +(
                /^$RE{vid}$/ ? sql('SELECT 1, id FROM vn WHERE id =', \"$+{id}") : (),
                sql('SELECT 1+substr_score(lower(title),', \sql_like($_), '), id FROM vnt WHERE c_search LIKE ALL (search_query(', \"$_", '))'),
            ), @q),
            ') x(prio, id)
           JOIN', vnt, 'v ON v.id = x.id
          WHERE', sql_and($data->{hidden} ? () : 'NOT v.hidden'), '
          GROUP BY v.id, v.title, v.alttitle, v.hidden
          ORDER BY MIN(x.prio), v.title
    ');
};

1;
