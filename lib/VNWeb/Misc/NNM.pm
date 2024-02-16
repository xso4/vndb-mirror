package VNWeb::Misc::NNM;

use VNWeb::Prelude;

sub list {
    tuwf->dbAlli(q{
        SELECT id, color, message
             , (extract('epoch' from date - now() + '1 minute'::interval)*1000)::int AS wait
          FROM nnm
         WHERE date > now() - '1 minute'::interval - '10 second'::interval
    });
}

js_api NNMGet => {}, sub { +{ list => list } };

js_api NNMSubmit => {
    color   => { default => undef, regex => qr/^#[a-fA-F0-9]{6}$/ },
    message => { sl => 1, maxlength => 250 },
}, sub {
    my ($data) = @_;
    return 'You may only submit one message per minute.' if tuwf->dbVali("
        SELECT 1
          FROM nnm
         WHERE date > now() - '1 minute'::interval
           AND ((ip).ip IS NOT DISTINCT FROM ", \tuwf->reqIP,
                auth ? (" OR uid IS NOT DISTINCT FROM ", \auth->uid) : (), "
               )"
    );
    tuwf->dbExeci('INSERT INTO nnm', {
        message => $data->{message},
        color => $data->{color},
        uid => scalar auth->uid,
        ip => ipinfo(),
    });
    +{}
};

1;
