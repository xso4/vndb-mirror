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
    form_ action => "/u$id/notify_options", method => 'POST', sub {
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


sub listing_ {
    my($id, $opt, $count, $list) = @_;

    my sub url { "/u$id/notifies?r=$opt->{r}&p=$_" }

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
                b_ class => 'grayedout', ' (Read notifications are automatically removed after one month)';
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
                    i_ $l->{title};
                    txt_ ' by ';
                    i_ user_displayname $l;
                };
            };
        } for @$list;
    }

    form_ action => "/u$id/notify_update", method => 'POST', sub {
        input_ type => 'hidden', class => 'hidden', name => 'url', value => do { local $_ = $opt->{p}; url };
        paginate_ \&url, $opt->{p}, [$count, 25], 't';
        div_ class => 'mainbox browse notifies', sub {
            table_ class => 'stripe', \&tbl_;
        };
        paginate_ \&url, $opt->{p}, [$count, 25], 'b';
    } if $count;
}


# Redirect so that elm/Subscribe.elm can link to this page without knowing our uid.
TUWF::get qr{/u/notifies}, sub { auth ? tuwf->resRedirect('/u'.auth->uid.'/notifies') : tuwf->resNotFound };


TUWF::get qr{/$RE{uid}/notifies}, sub {
    my $id = tuwf->capture('id');
    return tuwf->resNotFound if !auth || $id != auth->uid;

    my $opt = tuwf->validate(get =>
        p => { page => 1 },
        r => { anybool => 1 },
    )->data;

    my $where = sql_and(
        sql('n.uid =', \$id),
        $opt->{r} ? () : 'n.read IS NULL'
    );
    my $count = tuwf->dbVali('SELECT count(*) FROM notifications n WHERE', $where);
    my $list = tuwf->dbPagei({ results => 25, page => $opt->{p} },
       'SELECT n.id, n.ntype::text[] AS ntype, n.iid, n.num, t.title, ', sql_user(), '
             , ', sql_totime('n.date'), ' as date
             , ', sql_totime('n.read'), ' as read
          FROM notifications n, item_info(n.iid, n.num) t
          LEFT JOIN users u ON u.id = t.uid
         WHERE ', $where,
        'ORDER BY n.id', $opt->{r} ? 'DESC' : 'ASC'
    );

    framework_ title => 'My notifications', js => 1,
    sub {
        div_ class => 'mainbox', sub {
            h1_ 'My notifications';
            p_ class => 'browseopts', sub {
                a_ !$opt->{r} ? (class => 'optselected') : (), href => '?r=0', 'Unread notifications';
                a_  $opt->{r} ? (class => 'optselected') : (), href => '?r=1', 'All notifications';
            };
            p_ 'No notifications!' if !$count;
        };
        listing_ $id, $opt, $count, $list;
        div_ class => 'mainbox', sub { settings_ $id };
    };
};


TUWF::post qr{/$RE{uid}/notify_options}, sub {
    my $id = tuwf->capture('id');
    return tuwf->resNotFound if !auth || $id != auth->uid;

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
    tuwf->resRedirect("/u$id/notifies", 'post');
};


TUWF::post qr{/$RE{uid}/notify_update}, sub {
    my $id = tuwf->capture('id');
    return tuwf->resNotFound if !auth || $id != auth->uid;

    my $frm = tuwf->validate(post =>
        url       => { regex => qr{^/u$id/notifies} },
        notifysel => { required => 0, default => [], type => 'array', scalar => 1, values => { id => 1 } },
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
    return tuwf->resNotFound if !auth || $id != auth->uid;
    tuwf->dbExeci('UPDATE notifications SET read = NOW() WHERE read IS NULL AND uid =', \$id, ' AND id =', \tuwf->capture('num'));
    tuwf->resRedirect('/'.tuwf->capture('lid'), 'temp');
};



# It's a bit annoying to add auth->notiRead() to each revision page, so do that in bulk with a simple hook.
TUWF::hook before => sub {
    auth->notiRead($+{vndbid}, $+{rev}) if auth && tuwf->reqPath() =~ qr{^/(?<vndbid>[vrpcsd]$RE{num})\.(?<rev>$RE{num})$};
};




our $SUB = form_compile any => {
    id        => { vndbid => [qw|t w v r p c s d i|] },
    subnum    => { required => 0, jsonbool => 1 },
    subreview => { anybool => 1 },
    subapply  => { anybool => 1 },
    noti      => { uint => 1 }, # Whether the user already gets 'subnum' notifications for this entry (see HTML.pm for possible values)
};

elm_api Subscribe => undef, $SUB, sub {
    my($data) = @_;

    delete $data->{noti};
    $data->{subnum} = $data->{subnum}?1:0 if defined $data->{subnum}; # 'jsonbool' isn't understood by SQL
    $data->{subreview} = 0 if $data->{id} !~ /^v/;

    my %where = (iid => delete $data->{id}, uid => auth->uid);
    if(!defined $data->{subnum} && !$data->{subreview} && !$data->{subapply}) {
        tuwf->dbExeci('DELETE FROM notification_subs WHERE', \%where);
    } else {
        tuwf->dbExeci('INSERT INTO notification_subs', {%where, %$data}, 'ON CONFLICT (iid,uid) DO UPDATE SET', $data);
    }
    elm_Success
};

1;
