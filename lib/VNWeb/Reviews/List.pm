package VNWeb::Reviews::List;

use VNWeb::Prelude;


sub tablebox_ {
    my($opt, $lst, $count) = @_;

    my sub url { '?'.query_encode({%$opt, @_}) }

    paginate_ \&url, $opt->{p}, [$count, 50], 't';
    article_ class => 'browse reviewlist', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub { txt_ 'Date'; sortable_ 'id', $opt, \&url; debug_ $lst };
                td_ class => 'tc2', 'By';
                td_ class => 'tc3', 'Vote';
                td_ class => 'tc4', 'Type';
                td_ class => 'tc5', 'Review';
                td_ class => 'tc6', sub { txt_ 'Score*';  sortable_ 'rating', $opt, \&url } if auth->isMod;
                td_ class => 'tc7', 'C#';
                td_ class => 'tc8', sub { txt_ 'Last comment'; sortable_ 'lastpost', $opt, \&url };
            } };
            tr_ sub {
                td_ class => 'tc1', fmtdate $_->{date}, 'compact';
                td_ class => 'tc2', sub { user_ $_ };
                td_ class => 'tc3', fmtvote $_->{vote};
                td_ class => 'tc4', [qw/Short Medium Long/]->[$_->{length}];
                td_ class => 'tc5', sub { a_ href => "/$_->{id}", tattr $_; small_ ' (flagged)' if $_->{c_flagged} };
                td_ class => 'tc6', sprintf '👍 %.2f 👎 %.2f', $_->{c_up}/100, $_->{c_down}/100 if auth->isMod;
                td_ class => 'tc7', $_->{c_count};
                td_ class => 'tc8', $_->{c_lastnum} ? sub {
                    user_ $_, 'lu_';
                    txt_ ' @ ';
                    a_ href => "/$_->{id}.$_->{c_lastnum}#last", fmtdate $_->{ldate}, 'full';
                } :  '';
            } for @$lst;
        };
    };
    paginate_ \&url, $opt->{p}, [$count, 50], 'b';
}


FU::get '/w', sub {
    my $opt = fu->query(
        p => { page => 1 },
        s => { onerror => 'id', enum => [qw[id lastpost rating]] },
        o => { onerror => 'd',  enum => [qw[a d]] },
        u => { onerror => 0, vndbid => 'u' },
    );
    $opt->{s} = 'id' if $opt->{s} eq 'rating' && !auth->isMod;

    my $u = $opt->{u} && fu->SQL('SELECT id, ', USER, 'FROM users u WHERE id =', $opt->{u})->rowh;
    fu->notfound if $opt->{u} && (!$u || (!$u->{user_name} && !auth->isMod));

    my $where = AND
        $u ? SQL 'w.uid =', $u->{id} : (),
        auth->isMod ? () : 'NOT w.c_flagged';
    my $count = fu->SQL('SELECT COUNT(*) FROM reviews w WHERE', $where)->val;
    my $lst = fu->SQL('
        SELECT w.id, w.vid, w.length, w.c_up, w.c_down, w.c_flagged, w.c_count, w.c_lastnum
             , v.title, uv.vote, ', USER, ', w.date
             , ', USER('wpu','lu_'), ', wp.date as ldate
          FROM reviews w
          JOIN', VNT, 'v ON v.id = w.vid
          LEFT JOIN users u ON u.id = w.uid
          LEFT JOIN reviews_posts wp ON w.id = wp.id AND w.c_lastnum = wp.num
          LEFT JOIN users wpu ON wpu.id = wp.uid
          LEFT JOIN ulist_vns uv ON uv.uid = w.uid AND uv.vid = w.vid
         WHERE', $where, '
         ORDER BY', RAW({id => 'w.id', lastpost => 'wp.date', rating => 'w.c_up-w.c_down'}->{$opt->{s}}), $opt->{o} eq 'a' ? 'ASC' : 'DESC', 'NULLS LAST
         LIMIT 50 OFFSET', 50*($opt->{p}-1)
    )->allh;

    my $title = $u ? 'Reviews by '.user_displayname($u) : 'Browse reviews';
    framework_ title => $title, $u ? (dbobj => $u, tab => 'reviews') : (), sub {
        article_ sub {
            h1_ $title;
            if($u && !$count) {
                p_ +(auth && $u->{id} eq auth->uid ? 'You have' : user_displayname($u).' has').' not submitted any reviews yet.';
            }
            p_ 'Note: The score column is only visible to moderators.' if $count && auth->isMod;
        };
        tablebox_ $opt, $lst, $count if $count;
    };
};

1;
