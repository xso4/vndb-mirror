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
        'SELECT v.id, v.title, v.original, v.hidden
           FROM (',
			sql_join('UNION ALL', map {
                my $qs = sql_like $_;
                my @qs = normalize_query $_;
                (
                    /^$RE{vid}$/ ? sql('SELECT 1, id FROM vn WHERE id =', \"$+{id}") : (),
                    sql('SELECT 1+substr_score(lower(title),', \$qs, '), id FROM vn WHERE title ILIKE', \"$qs%"),
                    @qs ? (sql 'SELECT 10, id FROM vn WHERE', sql_and map sql('c_search ILIKE', \"%$_%"), @qs) : ()
                )
            } @q),
            ') x(prio, id)
           JOIN vn v ON v.id = x.id
          WHERE', sql_and($data->{hidden} ? () : 'NOT v.hidden'), '
          GROUP BY v.id, v.title, v.original, v.hidden
          ORDER BY MIN(x.prio), v.title
    ');
};


our $LENGTHVOTE = form_compile any => {
    uid    => { vndbid => 'u' },
    vid    => { vndbid => 'v' },
    vote   => { type => 'hash', required => 0, keys => {
        rid    => { vndbid => 'r' },
        length => { uint => 1, range => [1,32767] },
        speed  => { uint => 1, enum => [0,1,2] },
        notes  => { required => 0, default => '' },
    } },
};

elm_api VNLengthVote => undef, $LENGTHVOTE, sub {
    my($data) = @_;
    return elm_Unauth if !auth->permLengthvote || $data->{uid} ne auth->uid;
    my %where = ( uid => $data->{uid}, vid => $data->{vid} );
    tuwf->dbExeci('DELETE FROM vn_length_votes WHERE', \%where) if !$data->{vote};
    tuwf->dbExeci(
        'INSERT INTO vn_length_votes', { %where, $data->{vote}->%* },
        'ON CONFLICT (uid, vid) DO UPDATE SET', $data->{vote}
    ) if $data->{vote};
    return elm_Success;
};

1;
