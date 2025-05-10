package VNWeb::Discussions::UPosts;

use VNWeb::Prelude;


sub listing_ {
    my($count, $list, $page) = @_;

    my sub url { '?'.query_encode({@_}) }

    paginate_ \&url, $page, [ $count, 50 ], 't';
    article_ class => 'browse uposts', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub { debug_ $list };
                td_ class => 'tc2', '';
                td_ class => 'tc3', 'Date';
                td_ class => 'tc4', 'Title';
            }};
            tr_ sub {
                my $url = "/$_->{id}.$_->{num}";
                td_ class => 'tc1', sub { a_ href => $url, $_->{hidden} ? (class => 'grayedout') : (), $_->{id} };
                td_ class => 'tc2', sub { a_ href => $url, $_->{hidden} ? (class => 'grayedout') : (), '.'.$_->{num} };
                td_ class => 'tc3', fmtdate $_->{date};
                td_ class => 'tc4', sub {
                    a_ href => $url, $_->{title};
                    small_ sub { lit_ bb_format $_->{msg}, maxlength => 150, inline => 1 };
                };
            } for @$list;
        }
    };

    paginate_ \&url, $page, [ $count, 50 ], 'b';
}


FU::get qr{/$RE{uid}/posts}, sub($uid) {
    not_moe;
    my $u = fu->SQL('SELECT id, ', USER, 'FROM users u WHERE id =', $uid)->rowh;
    fu->notfound if !$u || (!$u->{user_name} && !auth->isMod);

    my $page = fu->query(p => { upage => 1 });

    my $sql = SQL '(
        SELECT tp.tid, tp.num, tp.msg, t.title, tp.date, t.hidden OR tp.hidden IS NOT NULL
          FROM threads_posts tp
          JOIN threads t ON t.id = tp.tid
         WHERE tp.uid =', $u->{id}, 'AND NOT t.private', auth->permBoardmod ? () : 'AND NOT t.hidden AND tp.hidden IS NULL', '
       UNION ALL
        SELECT rp.id, rp.num, rp.msg, v.title[1+1], rp.date, rp.hidden IS NOT NULL
          FROM reviews_posts rp
          JOIN reviews r ON r.id = rp.id
          JOIN', VNT, 'v ON v.id = r.vid
         WHERE rp.uid =', $u->{id}, auth->permBoardmod ? () : 'AND rp.hidden IS NULL', '
       ) p(id,num,msg,title,date,hidden)';

    my $count = fu->SQL('SELECT count(*) FROM', $sql)->val;
    my $list = $count && fu->SQL(
        'SELECT id, num, substring(msg from 1 for 1000) as msg, title, date, hidden
           FROM ', $sql, '
          ORDER BY date DESC
          LIMIT 50 OFFSET', 50*($page+1)
    )->allh;

    my $own = auth && $u->{id} eq auth->uid;
    my $title = $own ? 'My posts' : 'Posts by '.user_displayname $u;
    framework_ title => $title, dbobj => $u, tab => 'posts',
    sub {
        article_ sub {
            h1_ $title;
            if(!$count) {
                p_ +($own ? 'You have' : user_displayname($u).' has').' not posted anything on the forums yet.';
            }
        };

        listing_ $count, $list, $page if $count;
    };
};


1;
