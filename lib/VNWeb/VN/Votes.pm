package VNWeb::VN::Votes;

use VNWeb::Prelude;


sub listing_($opt, $count, $lst) {
    my sub url { '?'.query_encode({%$opt, @_}) }
    paginate_ \&url, $opt->{p}, [ $count, 50 ], 't';
    article_ class => 'browse votelist', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub { txt_ 'Date'; sortable_ 'date',  $opt, \&url; debug_ $lst };
                td_ class => 'tc2', sub { txt_ 'Vote'; sortable_ 'vote',  $opt, \&url; };
                td_ class => 'tc3', sub { txt_ 'User'; sortable_ 'title', $opt, \&url; };
            } };
            tr_ sub {
                td_ class => 'tc1', fmtdate $_->{date};
                td_ class => 'tc2', fmtvote $_->{vote};
                td_ class => 'tc3', sub {
                    small_ 'hidden' if $_->{c_private};
                    user_ $_ if !$_->{c_private};
                };
            } for @$lst;
        };
    };
    paginate_ \&url, $opt->{p}, [ $count, 50 ], 'b';
}


FU::get qr{/$RE{vid}/votes}, sub($id) {
    my $v = dbobj $id;
    fu->notfound if !$v->{id} || $v->{entry_hidden};

    my $opt = fu->query(
        p => { page => 1 },
        o => { onerror => 'd', enum => ['a','d'] },
        s => { onerror => 'date', enum => ['date', 'title', 'vote' ] }
    );

    my $fromwhere = SQL
        'FROM ulist_vns uv
         JOIN users u ON u.id = uv.uid
        WHERE uv.vid =', $v->{id}, 'AND uv.vote IS NOT NULL
          AND NOT EXISTS(SELECT 1 FROM users u WHERE u.id = uv.uid AND u.ign_votes)';

    my $count = fu->SQL('SELECT COUNT(*)', $fromwhere)->val;

    my $lst = fu->SQL(
      'SELECT uv.vote, uv.c_private, uv.vote_date as date, ', USER,
           $fromwhere, 'ORDER BY', RAW(sprintf
            { date => 'uv.vote_date %s, uv.vote', vote => 'uv.vote %s, uv.vote_date', title => "(CASE WHEN uv.c_private THEN NULL ELSE u.username END) %s, uv.vote_date" }->{$opt->{s}},
            { a => 'ASC', d => 'DESC' }->{$opt->{o}}),
       'LIMIT 50 OFFSET', 50*($opt->{p}-1)
    )->allh;

    framework_ title => "Votes for $v->{title}[1]", dbobj => $v, sub {
        article_ sub {
            h1_ "Votes for $v->{title}[1]";
            p_ 'No votes to list. :(' if !@$lst;
        };
        listing_ $opt, $count, $lst if @$lst;
    };
};


1;
