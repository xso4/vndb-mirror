package VNWeb::User::Notifications;

use VNWeb::Prelude;

sub settings_($id) {
    h1_ 'Settings';
    form_ action => "/$id/notify_options", method => 'POST', sub {
        input_ type => 'hidden', class => 'hidden', name => 'csrf', value => auth->csrftoken;

        my $opt = auth->pref('notifyopts');
        table_ class => 'notifysettings', sub {
            for my ($id, $v) (%NTYPE) {
                tr_ class => 'hdr', sub { td_ colspan => 5, sub { strong_ 'Database' } } if $id eq 'listdel';
                tr_ class => 'hdr', sub { td_ colspan => 5, sub { strong_ 'Community' } } if $id eq 'pm';
                tr_ class => 'hdr', sub { td_ colspan => 5, sub {
                    strong_ 'Subscriptions';
                    small_ ' (Managed with the 🔔 icon at the top of database, forum and review pages)';
                } } if $id eq 'subedit';
                tr_ class => $id eq 'announce' ? undef : 'sub', sub {
                    my $o = notifyopt $id => $opt;
                    td_ sub { $v->{desc} ? abbr_ title => $v->{desc}, $v->{txt} : txt_ $v->{txt} };
                    td_ sub { label_ sub { input_ type => 'radio', name => "opt_$id", value => 0, checked => $o == 0 ? 'checked' : undef; txt_ ' mute' } if $v->{mute} };
                    td_ sub { label_ sub { input_ type => 'radio', name => "opt_$id", value => 1, checked => $o == 1 ? 'checked' : undef; txt_ ' low' } };
                    td_ sub { label_ sub { input_ type => 'radio', name => "opt_$id", value => 2, checked => $o == 2 ? 'checked' : undef; txt_ ' medium' } };
                    td_ sub { label_ sub { input_ type => 'radio', name => "opt_$id", value => 3, checked => $o == 3 ? 'checked' : undef; txt_ ' high' } };
                };
            }
            tfoot_ sub { tr_ sub { td_ colspan => 5, sub {
                input_ type => 'submit', class => 'submit', value => 'Save';
                small_ ' (Settings are applied to new notifications)';
            }}};
        };
    };
}


sub listing_($id, $opt, $count, $list, $page, $url) {
    my sub tbl_ {
        thead_ sub { tr_ sub {
            td_ '';
            td_ 'Type';
            td_ 'Age';
            td_ colspan => 2, 'ID';
            td_ 'Action';
        }};
        tfoot_ sub { tr_ sub {
            td_ colspan => 6, sub {
                input_ type => 'checkbox', class => 'checkall', name => 'notifysel', value => 0;
                txt_ ' ';
                input_ type => 'submit', class => 'submit', name => 'markread', value => 'mark selected read' if $page eq 'unread';
                input_ type => 'submit', class => 'submit', name => 'remove', value => 'remove selected';
                small_ ' (Read notifications are automatically removed after one month)' if $page eq 'read';
            }
        }};
        tr_ sub {
            my $l = $_;
            my $lid = $l->{iid}.($l->{num}?'.'.$l->{num}:'');
            td_ class => 'tc1', sub { input_ type => 'checkbox', name => 'notifysel', value => $l->{id}; };
            td_ class => 'tc2', '+' => $l->{prio} == 3 ? 'standout' : $l->{prio} == 1 ? 'grayedout' : undef, sub {
                # Hide some not very interesting overlapping notification types
                my %t = map +($_,1), $l->{ntype}->@*;
                delete $t{subpost} if $t{post} || $t{comment} || $t{pm};
                delete $t{post}    if $t{pm};
                delete $t{subedit} if $t{dbedit};
                delete $t{dbedit} if $t{dbdel};
                join_ \&br_, sub { txt_ $NTYPE{$_}{txt} }, sort keys %t;
            };
            td_ class => 'tc3', sub { age_ $l->{date} };
            td_ class => 'tc4', sub { a_ href => "/$lid", $l->{iid} };
            td_ class => 'tc5', sub { a_ href => "/$lid", '.'.$l->{num} if $l->{num} };
            td_ class => 'tc6', sub {
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
        article_ class => 'browse notifies', sub {
            table_ class => 'stripe', \&tbl_;
        };
        paginate_ $url, $opt->{p}, [$count, 100], 'b';
    } if $count;
}


# Redirect so that the 'Subscribe' widget can link to this page without knowing our uid.
FU::get '/u/notifies', sub { auth ? fu->redirect(temp => '/'.auth->uid.'/notifies') : fu->notfound };


FU::get qr{/$RE{uid}/notifies(?:/(read|settings))?}, sub($id, $page='unread') {
    fu->notfound if !auth || $id ne auth->uid;

    my $opt = fu->query(
        p => { page => 1 },
        l => { onerror => 0, range => [0,3] },
    );

    my $where = $page ne 'settings' && SQL 'n.uid =', $id, 'AND n.read IS', $page eq 'read' ? 'NOT NULL' : 'NULL';
    my $count = !$where ? [0] : fu->SQL('
        SELECT count(*)
             , count(*) FILTER (WHERE prio = 1)
             , count(*) FILTER (WHERE prio = 2)
             , count(*) FILTER (WHERE prio = 3)
          FROM notifications n WHERE', $where
    )->rowa;
    my $list = $count->[0] && fu->SQL(
       'SELECT n.id, n.ntype, n.iid, n.num, n.prio, n.date, t.title, ', USER, '
          FROM notifications n,', ITEM_INFO('n.iid', 'n.num'), 't
          LEFT JOIN users u ON u.id = t.uid
         WHERE ', $where, $opt->{l} ? ('AND n.prio =', $opt->{l}) : (),
        'ORDER BY ', $page eq 'read' ? 'n.id DESC' : 'n.prio DESC, n.id DESC',
        'LIMIT 100 OFFSET', 100*($opt->{p}-1)
    )->allh;

    my sub url { "/$id/notifies".($page eq 'read' ? '/read' : '').'?'.query_encode({%$opt, @_}) }

    framework_ title => 'My notifications', js => 1,
    sub {
        article_ sub { h1_ 'My notifications'; };
        nav_ sub {
            menu_ sub {
                my $pre = '/'.auth->uid.'/notifies';
                li_ sub { a_ href => $pre,            class => $page eq 'unread'   ? 'highlightselected' : undef, 'Unread' };
                li_ sub { a_ href => "$pre/read",     class => $page eq 'read'     ? 'highlightselected' : undef, 'Read' };
                li_ sub { a_ href => "$pre/settings", class => $page eq 'settings' ? 'highlightselected' : undef, 'Settings' };
            };
            menu_ sub {
                li_ sub { a_ href => url(p => 0, l => 1), class => $opt->{l} == 1 ? 'highlightselected' : undef, "Low ($count->[1])" } if $count->[1];
                li_ sub { a_ href => url(p => 0, l => 2), class => $opt->{l} == 2 ? 'highlightselected' : undef, "Medium ($count->[2])" } if $count->[2];
                li_ sub { a_ href => url(p => 0, l => 3), class => $opt->{l} == 3 ? 'highlightselected' : undef, "High ($count->[3])" } if $count->[3];
                li_ sub { a_ href => url(p => 0, l => 0), class => $opt->{l} == 0 ? 'highlightselected' : undef, 'All' };
            } if $count->[0];
        };
        if ($page eq 'settings') {
            article_ sub { settings_ $id }
        } elsif ($count->[0]) {
            listing_ $id, $opt, $count->[$opt->{l}], $list, $page, \&url;
        } else {
            article_ sub { p_ 'No notifications.' };
        }
    };
};


FU::post qr{/$RE{uid}/notify_options}, sub($id) {
    fu->notfound if !auth || $id ne auth->uid;

    my $frm = fu->formdata(
        csrf     => {},
        map +("opt_$_" => { range => [0,3] }), keys %NTYPE
    );
    fu->notfound if !auth->csrfcheck($frm->{csrf});

    my $opt = 0;
    for my ($id,$v) (%NTYPE) {
        $opt |= ($frm->{"opt_$id"} || ($v->{mute} ? 0 : 1)) << ($v->{opt}*2)
    }
    fu->SQL('UPDATE users SET notifyopts =', $opt, 'WHERE id =', $id)->exec;
    fu->redirect(tempget => "/$id/notifies/settings");
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
