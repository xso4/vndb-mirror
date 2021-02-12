package VNWeb::Discussions::UPosts;

use VNWeb::Prelude;


sub listing_ {
    my($count, $list, $page) = @_;

    my sub url { '?'.query_encode @_ }

    paginate_ \&url, $page, [ $count, 50 ], 't';
    div_ class => 'mainbox browse uposts', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub { debug_ $list };
                td_ class => 'tc2', '';
                td_ class => 'tc3', 'Date';
                td_ class => 'tc4', 'Title';
            }};
            tr_ sub {
                my $url = "/$_->{id}.$_->{num}";
                td_ class => 'tc1', sub { a_ href => $url, $_->{id} };
                td_ class => 'tc2', sub { a_ href => $url, '.'.$_->{num} };
                td_ class => 'tc3', fmtdate $_->{date};
                td_ class => 'tc4', sub {
                    a_ href => $url, $_->{title};
                    b_ class => 'grayedout', sub { lit_ bb_format $_->{msg}, maxlength => 150, inline => 1 };
                };
            } for @$list;
        }
    };

    paginate_ \&url, $page, [ $count, 50 ], 'b';
}


TUWF::get qr{/$RE{uid}/posts}, sub {
    my $u = tuwf->dbRowi('SELECT id, ', sql_user(), 'FROM users u WHERE id =', \tuwf->capture('id'));
    return tuwf->resNotFound if !$u->{id};

    my $page = tuwf->validate(get => p => { upage => 1 })->data;

    my $sql = sql '(
        SELECT tp.tid, tp.num, tp.msg, t.title, tp.date
          FROM threads_posts tp
          JOIN threads t ON t.id = tp.tid
         WHERE NOT t.private AND NOT t.hidden AND NOT tp.hidden AND tp.uid =', \$u->{id}, '
       UNION ALL
        SELECT rp.id, rp.num, rp.msg, v.title, rp.date
          FROM reviews_posts rp
          JOIN reviews r ON r.id = rp.id
          JOIN vn v ON v.id = r.vid
         WHERE NOT rp.hidden AND rp.uid =', \$u->{id}, '
       ) p(id,num,msg,title,date)';

    my $count = tuwf->dbVali('SELECT count(*) FROM', $sql);
    my $list = $count && tuwf->dbPagei({ results => 50, page => $page },
        'SELECT id, num, substring(msg from 1 for 1000) as msg, title, ', sql_totime('date'), 'as date
           FROM ', $sql, 'ORDER BY date DESC'
    );

    my $own = auth && $u->{id} eq auth->uid;
    my $title = $own ? 'My posts' : 'Posts by '.user_displayname $u;
    framework_ title => $title, type => 'u', dbobj => $u, tab => 'posts',
    sub {
        div_ class => 'mainbox', sub {
            h1_ $title;
            if(!$count) {
                p_ +($own ? 'You have' : user_displayname($u).' has').' not posted anything on the forums yet.';
            }
        };

        listing_ $count, $list, $page if $count;
    };
};


1;
