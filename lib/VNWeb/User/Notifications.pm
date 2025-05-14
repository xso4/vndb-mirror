package VNWeb::User::Notifications;

use VNWeb::Prelude;

my %ntypes = (
    pm        => 'Message on your board',
    dbdel     => 'Entry you contributed to has been deleted',
    listdel   => 'VN in your list has been deleted',
    dbedit    => 'Entry you contributed to has been edited',
    announce  => 'Site announcement',
    post      => 'Reply to a thread you posted in',
    comment   => 'Comment on your review',
    subpost   => 'Reply to a thread you subscribed to',
    subedit   => 'Entry you subscribed to has been edited',
    subreview => 'New review for a VN you subscribed to',
    subapply  => 'Trait you subscribed to has been (un)applied',
);


sub settings_($id) {
    my $u = fu->sql('SELECT notify_dbedit, notify_post, notify_comment, notify_announce FROM users WHERE id = $1', $id)->rowh;

    h1_ 'Settings';
    form_ action => "/$id/notify_options", method => 'POST', sub {
        input_ type => 'hidden', class => 'hidden', name => 'csrf', value => auth->csrftoken;
        p_ sub {
            label_ sub {
                input_ type => 'checkbox', name => 'dbedit', $u->{notify_dbedit} ? (checked => 'checked') : ();
                txt_ ' Notify me about edits of database entries I contributed to.';
            };
            br_;
            label_ sub {
                input_ type => 'checkbox', name => 'post', $u->{notify_post} ? (checked => 'checked') : ();
                txt_ ' Notify me about replies to threads I posted in.';
            };
            br_;
            label_ sub {
                input_ type => 'checkbox', name => 'comment', $u->{notify_comment} ? (checked => 'checked') : ();
                txt_ ' Notify me about comments to my reviews.';
            };
            br_;
            label_ sub {
                input_ type => 'checkbox', name => 'announce', $u->{notify_announce} ? (checked => 'checked') : ();
                txt_ ' Notify me about site announcements.';
            };
            br_;
            input_ type => 'submit', class => 'submit', value => 'Save';
        }
    };
}


sub stats_($stats, $opt, $url) {
    table_ class => 'usernotifies', sub {
        thead_ sub { tr_ sub {
            td_ '';
            td_ 'Unread';
            td_ 'Total';
        }};
        for (@$stats) {
            my $nsel = +($_->{ntype}||'') eq ($opt->{n}||'');
            tr_ class => $nsel ? 'sel' : undef, sub {
                td_ sub {
                    em_ 'All types' if !$_->{ntype};
                    txt_ $ntypes{$_->{ntype}} if $_->{ntype};
                };
                td_ class => $nsel && !$opt->{r} ? 'sel' : undef, sub {
                    txt_ 0 if !$_->{unread};
                    a_ href => $url->(p=>undef,r=>undef,n=>$_->{ntype}), $_->{unread} if $_->{unread};
                };
                td_ class => $nsel && $opt->{r} ? 'sel' : undef, sub {
                    txt_ 0 if !$_->{all};
                    a_ href => $url->(p=>undef,r=>1,n=>$_->{ntype}), $_->{all} if $_->{all};
                };
            }
        };
    };
}


sub listing_($id, $opt, $count, $list, $url) {
    my sub tbl_ {
        thead_ sub { tr_ sub {
            td_ '';
            td_ 'Type';
            td_ 'Age';
            td_ 'ID';
            td_ 'Action';
        }};
        tfoot_ sub { tr_ sub {
            td_ colspan => 5, sub {
                input_ type => 'checkbox', class => 'checkall', name => 'notifysel', value => 0;
                txt_ ' ';
                input_ type => 'submit', class => 'submit', name => 'markread', value => 'mark selected read';
                input_ type => 'submit', class => 'submit', name => 'remove', value => 'remove selected';
                small_ ' (Read notifications are automatically removed after one month)';
            }
        }};
        tr_ $_->{read} ? () : (class => 'unread'), sub {
            my $l = $_;
            my $lid = $l->{iid}.($l->{num}?'.'.$l->{num}:'');
            td_ class => 'tc1', sub { input_ type => 'checkbox', name => 'notifysel', value => $l->{id}; };
            td_ class => 'tc2', sub {
                # Hide some not very interesting overlapping notification types
                my %t = map +($_,1), $l->{ntype}->@*;
                delete $t{subpost} if $t{post} || $t{comment} || $t{pm};
                delete $t{post}    if $t{pm};
                delete $t{subedit} if $t{dbedit};
                delete $t{dbedit} if $t{dbdel};
                join_ \&br_, sub { txt_ $ntypes{$_} }, sort keys %t;
            };
            td_ class => 'tc3', fmtage $l->{date};
            td_ class => 'tc4', sub { a_ href => "/$lid", $lid };
            td_ class => 'tc5', sub {
                a_ href => "/$lid", sub {
                    txt_ $l->{iid} =~ /^w/ ? ($l->{num} ? 'Comment on ' : 'Review of ') :
                         $l->{iid} =~ /^t/ ? ($l->{num} == 1 ? 'New thread ' : 'Reply to ') : 'Edit of ';
                    span_ tattr $l;
                    txt_ ' by ';
                    span_ user_displayname $l;
                };
            };
        } for @$list;
    }

    form_ action => "/$id/notify_update", method => 'POST', sub {
        input_ type => 'hidden', class => 'hidden', name => 'url', value => $url->();
        paginate_ $url, $opt->{p}, [$count, 25], 't';
        article_ class => 'browse notifies', sub {
            table_ class => 'stripe', \&tbl_;
        };
        paginate_ $url, $opt->{p}, [$count, 25], 'b';
    } if $count;
}


# Redirect so that the 'Subscribe' widget can link to this page without knowing our uid.
FU::get '/u/notifies', sub { auth ? fu->redirect(temp => '/'.auth->uid.'/notifies') : fu->notfound };


FU::get qr{/$RE{uid}/notifies}, sub($id) {
    fu->notfound if !auth || $id ne auth->uid;

    my $opt = fu->query(
        p => { page => 1 },
        r => { anybool => 1 },
        n => { default => undef, enum => \%ntypes },
    );

    my $stats = fu->sql('
        SELECT x.ntype, count(*) filter (where n.read IS NULL) AS unread, count(*) AS all
          FROM notifications n, unnest(n.ntype) x(ntype)
         WHERE n.uid = $1
         GROUP BY GROUPING SETS ((), (x.ntype))
         ORDER BY count(*) DESC', $id
    )->allh;

    my($count) = map $_->{ $opt->{r} ? 'all' : 'unread'}, grep +($_->{ntype}||'') eq ($opt->{n}||''), @$stats;
    $count ||= 0;
    my $list = $count && fu->SQL(
       'SELECT n.id, n.ntype, n.iid, n.num, n.date, n.read, t.title, ', USER, '
          FROM notifications n,', ITEM_INFO('n.iid', 'n.num'), 't
          LEFT JOIN users u ON u.id = t.uid
         WHERE ', AND(
             SQL('n.uid =', $id),
             $opt->{r} ? () : 'n.read IS NULL',
             $opt->{n} ? SQL('n.ntype && ARRAY[', $opt->{n}, '::notification_ntype]') : (),
         ),
        'ORDER BY n.id', $opt->{r} ? 'DESC' : 'ASC',
        'LIMIT 25 OFFSET', 25*($opt->{p}-1)
    )->allh;

    my sub url { "/$id/notifies?".query_encode({%$opt, @_}) }

    framework_ title => 'My notifications', js => 1,
    sub {
        article_ sub {
            h1_ 'My notifications';
            stats_ $stats, $opt, \&url if grep $_->{all}, @$stats;
            p_ 'No notifications!' if !$count;
        };
        listing_ $id, $opt, $count, $list, \&url;
        article_ sub { settings_ $id };
    };
};


FU::post qr{/$RE{uid}/notify_options}, sub($id) {
    fu->notfound if !auth || $id ne auth->uid;

    my $frm = fu->formdata(
        csrf     => {},
        dbedit   => { anybool => 1 },
        announce => { anybool => 1 },
        post     => { anybool => 1 },
        comment  => { anybool => 1 },
    );
    fu->notfound if !auth->csrfcheck($frm->{csrf});

    fu->SQL('UPDATE users', SET({
        notify_dbedit   => $frm->{dbedit},
        notify_announce => $frm->{announce},
        notify_post     => $frm->{post},
        notify_comment  => $frm->{comment},
    }), 'WHERE id =', $id)->exec;
    fu->redirect(tempget => "/$id/notifies");
};


FU::post qr{/$RE{uid}/notify_update}, sub($id) {
    fu->notfound if !auth || $id ne auth->uid;

    my $frm = fu->formdata(
        url       => { regex => qr{^/$id/notifies} },
        notifysel => { default => [], accept_scalar => 1, elems => { id => 1 } },
        markread  => { anybool => 1 },
        remove    => { anybool => 1 },
    );

    if($frm->{notifysel}->@*) {
        my $where = SQL 'uid =', $id, ' AND id', IN $frm->{notifysel};
        fu->SQL('DELETE FROM notifications WHERE', $where)->exec if $frm->{remove};
        fu->SQL('UPDATE notifications SET read = NOW() WHERE', $where)->exec if $frm->{markread};
    }
    fu->redirect(tempget => $frm->{url});
};



# It's a bit annoying to add auth->notiRead() to each revision page, so do that in bulk with a simple hook.
FU::before_request {
    auth->notiRead($+{vndbid}, $+{rev}) if auth && fu->path =~ qr{^/(?<vndbid>[vrpcsdgi]$RE{num})\.(?<rev>$RE{num})$};
};




our $SUB = form_compile {
    id        => { vndbid => [qw|t w v r p c s d i g|] },
    subnum    => { undefbool => 1 },
    subreview => { anybool => 1 },
    subapply  => { anybool => 1 },
    noti      => { uint => 1, default => undef }, # used by the widget, ignored in the backend
};

js_api Subscribe => $SUB, sub($data) {
    $data->{subreview} = 0 if $data->{id} !~ /^v/;
    delete $data->{noti};

    my %where = (iid => delete $data->{id}, uid => auth->uid);
    if(!defined $data->{subnum} && !$data->{subreview} && !$data->{subapply}) {
        fu->SQL('DELETE FROM notification_subs', WHERE \%where)->exec;
    } else {
        fu->SQL('INSERT INTO notification_subs', VALUES({%where, %$data}), 'ON CONFLICT (iid,uid) DO UPDATE', SET $data)->exec;
    }
    {};
};

1;
