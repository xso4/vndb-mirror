package VNWeb::User::Notifications;

use VNWeb::Prelude;

sub settings_($id) {
    h1_ 'Notification Settings';
    form_ action => "/$id/notify_options", method => 'POST', sub {
        input_ type => 'hidden', class => 'hidden', name => 'csrf', value => auth->csrftoken;

        my $opt = auth->pref('notifyopts');
        table_ class => 'notifysettings', sub {
            for my ($id, $v) (%NTYPE) {
                tr_ class => 'hdr', sub { td_ colspan => 5, sub { strong_ 'Database' } } if $id eq 'listdel';
                tr_ class => 'hdr', sub { td_ colspan => 5, sub { strong_ 'Community' } } if $id eq 'pm';
                tr_ class => $id eq 'announce' ? undef : 'sub', sub {
                    my $o = notifyopt $id => $opt;
                    td_ sub { $v->{desc} ? abbr_ title => $v->{desc}, $v->{txt} : txt_ $v->{txt} };
                    td_ sub { label_ sub { input_ type => 'radio', name => "opt_$id", value => 0, checked => $o == 0 ? 'checked' : undef; txt_ ' mute' } if $v->{mute} };
                    td_ sub { label_ sub { input_ type => 'radio', name => "opt_$id", value => 1, checked => $o == 1 ? 'checked' : undef; txt_ ' low' } };
                    td_ sub { label_ sub { input_ type => 'radio', name => "opt_$id", value => 2, checked => $o == 2 ? 'checked' : undef; txt_ ' medium' } };
                    td_ sub { label_ sub { input_ type => 'radio', name => "opt_$id", value => 3, checked => $o == 3 ? 'checked' : undef; txt_ ' high' } };
                };
            }
            tfoot_ sub { tr_ sub { td_ sub {
                input_ type => 'submit', class => 'submit', value => 'Save';
            }}};
        };
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
                    txt_ $NTYPE{$_->{ntype}}{txt} if $_->{ntype};
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
                join_ \&br_, sub { txt_ $NTYPE{$_}{txt} }, sort keys %t;
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
        n => { default => undef, enum => \%NTYPE },
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
        map +("opt_$_" => { range => [0,3] }), keys %NTYPE
    );
    fu->notfound if !auth->csrfcheck($frm->{csrf});

    my $opt = 0;
    for my ($id,$v) (%NTYPE) {
        $opt |= ($frm->{"opt_$id"} || ($v->{mute} ? 0 : 1)) << ($v->{opt}*2)
    }
    fu->SQL('UPDATE users SET notifyopts =', $opt, 'WHERE id =', $id)->exec;
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
