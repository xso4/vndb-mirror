package VNWeb::VN::Elm;

use VNWeb::Prelude;

elm_api VN => undef, {
    search => { searchquerya => 1 },
    hidden => { anybool => 1 },
}, sub {
    my($data) = @_;
    die "No query" if !$data->{search};

    elm_VNResult tuwf->dbPagei({ results => $data->{hidden}?50:15, page => 1 },
        'SELECT v.id, v.title[1+1] AS title, v.hidden
           FROM', vnt, 'v', $data->{search}->sql_join('v', 'v.id'),
          $data->{hidden} ? () : 'WHERE NOT v.hidden', '
          ORDER BY sc.score DESC, v.sorttitle
    ');
};

1;
