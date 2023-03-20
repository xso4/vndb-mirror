package VNWeb::Producers::Elm;

use VNWeb::Prelude;

elm_api Producers => undef, {
    search => { searchquerya => 1 },
    hidden => { anybool => 1 },
}, sub {
    my($data) = @_;
    die "No query" if !$data->{search};

    elm_ProducerResult tuwf->dbPagei({ results => 15, page => 1 },
        'SELECT p.id, p.title[1+1] AS name, p.title[1+1+1+1] AS altname, p.hidden
           FROM', producerst, 'p', $data->{search}->sql_join('p', 'p.id'),
          $data->{hidden} ? () : 'WHERE NOT p.hidden', '
          ORDER BY sc.score DESC, p.sorttitle
    ');
};

1;
