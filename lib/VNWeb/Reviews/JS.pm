package VNWeb::Reviews::JS;

use VNWeb::Prelude;

our $VOTE = form_compile any => {
    id       => { vndbid => 'w' },
    my       => { undefbool => 1 },
    overrule => { anybool => 1 },
    mod      => { anybool => 1 },
};

js_api ReviewsVote => $VOTE, sub {
    my($data) = @_;
    my %id = (auth ? (uid => auth->uid) : (ip => norm_ip tuwf->reqIP), id => $data->{id});
    my %val = (vote => $data->{my}, overrule => auth->permBoardmod ? $data->{overrule} : 0, date => sql 'NOW()');
    tuwf->dbExeci(
        defined $data->{my}
        ? sql 'INSERT INTO reviews_votes', {%id,%val}, 'ON CONFLICT (id,', auth ? 'uid' : 'ip', ') DO UPDATE SET', \%val
        : sql 'DELETE FROM reviews_votes WHERE', \%id
    );
    +{}
};

1;
