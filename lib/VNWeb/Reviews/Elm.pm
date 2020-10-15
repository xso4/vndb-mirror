package VNWeb::Reviews::Elm;

use VNWeb::Prelude;

my $VOTE = {
    id       => { vndbid => 'w' },
    my       => { required => 0, jsonbool => 1 },
    overrule => { anybool => 1 },
    mod      => { _when => 'out', anybool => 1 },
};

my  $VOTE_IN  = form_compile in  => $VOTE;
our $VOTE_OUT = form_compile out => $VOTE;

elm_api ReviewsVote => $VOTE_OUT, $VOTE_IN, sub {
    my($data) = @_;
    my %id = (auth ? (uid => auth->uid) : (ip => tuwf->reqIP()), id => $data->{id});
    my %val = (vote => $data->{my}?1:0, overrule => auth->permBoardmod ? $data->{overrule}?1:0 : 0, date => sql 'NOW()');
    tuwf->dbExeci(
        defined $data->{my}
        ? sql 'INSERT INTO reviews_votes', {%id,%val}, 'ON CONFLICT (id,', auth ? 'uid' : 'ip', ') DO UPDATE SET', \%val
        : sql 'DELETE FROM reviews_votes WHERE', \%id
    );
    elm_Success
};

1;
