package VNWeb::VN::Votes;

use VNWeb::Prelude;


sub listing_ {
    my($opt, $count, $lst) = @_;

    my sub url { '?'.query_encode %$opt, @_ }
    paginate_ \&url, $opt->{p}, [ $count, 50 ], 't';
    div_ class => 'mainbox browse votelist', sub {
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
                    b_ class => 'grayedout', 'hidden' if $_->{hide_list};
                    user_ $_ if !$_->{hide_list};
                };
            } for @$lst;
        };
    };
    paginate_ \&url, $opt->{p}, [ $count, 50 ], 'b';
}


TUWF::get qr{/$RE{vid}/votes}, sub {
    my $id = tuwf->capture('id');
    my $v = tuwf->dbRowi('SELECT id, title, hidden AS entry_hidden, locked AS entry_locked FROM vn WHERE id =', \$id);
    return tuwf->resNotFound if !$v->{id} || $v->{hidden};

    my $opt = tuwf->validate(get =>
        p => { page => 1 },
        o => { onerror => 'd', enum => ['a','d'] },
        s => { onerror => 'date', enum => ['date', 'title', 'vote' ] }
    )->data;

    my $fromwhere = sql
        'FROM ulist_vns uv
         JOIN users u ON u.id = uv.uid
        WHERE uv.vid =', \$v->{id}, 'AND uv.vote IS NOT NULL
          AND NOT EXISTS(SELECT 1 FROM users u WHERE u.id = uv.uid AND u.ign_votes)';

    my $count = tuwf->dbVali('SELECT COUNT(*)', $fromwhere);

    my $hide_list = 'NOT EXISTS(SELECT 1 FROM ulist_vns_labels uvl JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl WHERE uvl.uid = uv.uid AND uvl.vid = uv.vid AND NOT ul.private)';
    my $lst = tuwf->dbPagei({results => 50, page => $opt->{p}},
      'SELECT uv.vote,', sql_totime('uv.vote_date'), 'as date, ', sql_user(), ", $hide_list AS hide_list
        ", $fromwhere, 'ORDER BY', sprintf
            { date => 'uv.vote_date %s', vote => 'uv.vote %s', title => "(CASE WHEN $hide_list THEN NULL ELSE u.username END) %s, uv.vote_date" }->{$opt->{s}},
            { a => 'ASC', d => 'DESC' }->{$opt->{o}}
    );

    framework_ title => "Votes for $v->{title}", dbobj => $v, sub {
        div_ class => 'mainbox', sub {
            h1_ "Votes for $v->{title}";
            p_ 'No votes to list. :(' if !@$lst;
        };
        listing_ $opt, $count, $lst if @$lst;
    };
};


1;
