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


sub settings_ {
    my $id = shift;

    my $u = tuwf->dbRowi('SELECT notify_dbedit, notify_post, notify_comment, notify_announce FROM users WHERE id =', \$id);

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
TUWF::get qr{/u/notifies}, sub { auth ? tuwf->resRedirect('/'.auth->uid.'/notifies', 'temp') : tuwf->resNotFound };


TUWF::get qr{/$RE{uid}/notifies}, sub {
    my $id = tuwf->capture('id');
    return tuwf->resNotFound if !auth || $id ne auth->uid;

    my $opt = tuwf->validate(get =>
        p => { page => 1 },
        r => { anybool => 1 },
        n => { default => undef, enum => \%ntypes },
    )->data;

    my $stats = tuwf->dbAlli('
        SELECT x.ntype, count(*) filter (where n.read IS NULL) AS unread, count(*) AS all
          FROM notifications n, unnest(n.ntype) x(ntype)
         WHERE n.uid = ', \$id, '
         GROUP BY GROUPING SETS ((), (x.ntype))
         ORDER BY count(*) DESC');

    my($count) = map $_->{ $opt->{r} ? 'all' : 'unread'}, grep +($_->{ntype}||'') eq ($opt->{n}||''), @$stats;
    $count ||= 0;
    my $list = $count && tuwf->dbPagei({ results => 25, page => $opt->{p} },
       'SELECT n.id, n.ntype::text[] AS ntype, n.iid, n.num, t.title, ', sql_user(), '
             , ', sql_totime('n.date'), ' as date
             , ', sql_totime('n.read'), ' as read
          FROM notifications n,', item_info('n.iid', 'n.num'), 't
          LEFT JOIN users u ON u.id = t.uid
         WHERE ', sql_and(
             sql('n.uid =', \$id),
             $opt->{r} ? () : 'n.read IS NULL',
             $opt->{n} ? sql('n.ntype && ARRAY[', \$opt->{n}, '::notification_ntype]') : (),
         ),
        'ORDER BY n.id', $opt->{r} ? 'DESC' : 'ASC'
    );

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


TUWF::post qr{/$RE{uid}/notify_options}, sub {
    my $id = tuwf->capture('id');
    return tuwf->resNotFound if !auth || $id ne auth->uid;

    my $frm = tuwf->validate(post =>
        csrf     => {},
        dbedit   => { anybool => 1 },
        announce => { anybool => 1 },
        post     => { anybool => 1 },
        comment  => { anybool => 1 },
    )->data;
    return tuwf->resNotFound if !auth->csrfcheck($frm->{csrf});

    tuwf->dbExeci('UPDATE users SET', {
        notify_dbedit   => $frm->{dbedit},
        notify_announce => $frm->{announce},
        notify_post     => $frm->{post},
        notify_comment  => $frm->{comment},
    }, 'WHERE id =', \$id);
    tuwf->resRedirect("/$id/notifies", 'post');
};


TUWF::post qr{/$RE{uid}/notify_update}, sub {
    my $id = tuwf->capture('id');
    return tuwf->resNotFound if !auth || $id ne auth->uid;

    my $frm = tuwf->validate(post =>
        url       => { regex => qr{^/$id/notifies} },
        notifysel => { default => [], accept_scalar => 1, elems => { id => 1 } },
        markread  => { anybool => 1 },
        remove    => { anybool => 1 },
    )->data;

    if($frm->{notifysel}->@*) {
        my $where = sql 'uid =', \$id, ' AND id IN', $frm->{notifysel};
        tuwf->dbExeci('DELETE FROM notifications WHERE', $where) if $frm->{remove};
        tuwf->dbExeci('UPDATE notifications SET read = NOW() WHERE', $where) if $frm->{markread};
    }
    tuwf->resRedirect($frm->{url}, 'post');
};


# XXX: Not currently used anymore, just visiting the destination pages will mark the relevant notifications as read
# (but that's subject to change in the future, so let's keep this around)
TUWF::get qr{/$RE{uid}/notify/$RE{num}/(?<lid>[a-z0-9\.]+)}, sub {
    my $id = tuwf->capture('id');
    return tuwf->resNotFound if !auth || $id ne auth->uid;
    tuwf->dbExeci('UPDATE notifications SET read = NOW() WHERE read IS NULL AND uid =', \$id, ' AND id =', \tuwf->capture('num'));
    tuwf->resRedirect('/'.tuwf->capture('lid'), 'temp');
};



# It's a bit annoying to add auth->notiRead() to each revision page, so do that in bulk with a simple hook.
TUWF::hook before => sub {
    auth->notiRead($+{vndbid}, $+{rev}) if auth && tuwf->reqPath() =~ qr{^/(?<vndbid>[vrpcsdgi]$RE{num})\.(?<rev>$RE{num})$};
};




our $SUB = form_compile any => {
    id        => { vndbid => [qw|t w v r p c s d i g|] },
    subnum    => { undefbool => 1 },
    subreview => { anybool => 1 },
    subapply  => { anybool => 1 },
    noti      => { uint => 1, default => undef }, # used by the widget, ignored in the backend
};

js_api Subscribe => $SUB, sub {
    my($data) = @_;
    $data->{subreview} = 0 if $data->{id} !~ /^v/;
    delete $data->{noti};

    my %where = (iid => delete $data->{id}, uid => auth->uid);
    if(!defined $data->{subnum} && !$data->{subreview} && !$data->{subapply}) {
        tuwf->dbExeci('DELETE FROM notification_subs WHERE', \%where);
    } else {
        tuwf->dbExeci('INSERT INTO notification_subs', {%where, %$data}, 'ON CONFLICT (iid,uid) DO UPDATE SET', $data);
    }
    {};
};

1;
