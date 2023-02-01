package VNWeb::Misc::Reports;

use VNWeb::Prelude;

my $reportsperday = 5;

my @STATUS = qw/new busy done dismissed/;


# Returns the object associated with the vndbid.num; Returns false if the object can't be reported.
sub obj {
    my($id, $num) = @_;
    my $o = tuwf->dbRowi('SELECT x.*, ', sql_user(), 'FROM', item_info(\$id, \$num), 'x LEFT JOIN users u ON u.id = x.uid');
    $o->{object} = $id;
    $o->{objectnum} = $num;
    my $can = !defined $o->{title} ? 0
            : $id =~ /^[vrpcsd]/ ? !$num
            : $id =~ /^w/ ? 1
            : $id =~ /^t/ ? $num && !$o->{hidden} : 0;
    $can && $o
}


sub obj_ {
    my($o) = @_;
    my $lnk = $o->{object} . ($o->{objectnum} ? ".$o->{objectnum}" : '');
    if($o->{object} =~ /^(?:$RE{wid}|$RE{tid})$/ && $o->{objectnum}) {
        txt_ 'Comment ';
        a_ href => "/$lnk", "#$o->{objectnum}";
        txt_ ' on ';
        a_ href => "/$lnk", $o->{title}||$o->{object};
        txt_ ' by ';
        user_ $o;

    } else {
        txt_ {qw/v VN r Release p Producer c Character s Staff d Doc w Review t Thread/}->{substr $o->{object}, 0, 1};
        txt_ ': ';
        a_ href => "/$lnk", $o->{title}||$lnk;
        if($o->{user_name}) {
            txt_ ' by ';
            user_ $o;
        }
    }
}


sub is_throttled {
    tuwf->dbVali('SELECT COUNT(*) FROM reports WHERE date > NOW()-\'1 day\'::interval AND', auth ? ('uid =', \auth->uid) : ('(ip).ip =', \tuwf->reqIP)) >= $reportsperday
}


my $FORM = form_compile any => {
    object   => {},
    objectnum=> { required => 0, uint => 1 },
    title    => {},
    reason   => { maxlength => 50 },
    message  => { required => 0, default => '', maxlength => 50000 },
    loggedin => { anybool => 1 },
};

elm_api Report => undef, $FORM, sub {
    return elm_Unauth if is_throttled;
    my($data) = @_;
    my $obj = obj $data->{object}, $data->{objectnum};
    return elm_Invalid if !$data;

    tuwf->dbExeci('INSERT INTO reports', {
        uid      => auth->uid,
        ip       => auth ? undef : ipinfo(),
        object   => $data->{object},
        objectnum=> $data->{objectnum},
        reason   => $data->{reason},
        message  => $data->{message},
    });
    elm_Success
};


TUWF::get qr{/report/(?<object>[vrpcsdtw]$RE{num})(?:\.(?<subid>$RE{num}))?}, sub {
    my $obj = obj tuwf->captures('object', 'subid');
    return tuwf->resNotFound if !$obj || config->{read_only};

    framework_ title => 'Submit report', sub {
        if(is_throttled) {
            div_ class => 'mainbox', sub {
                h1_ 'Submit report';
                p_ "Sorry, you can only submit $reportsperday reports per day. If you wish to report more, you can do so by sending an email to ".config->{admin_email}
            }
        } else {
            elm_ Report => $FORM, { elm_empty($FORM)->%*, %$obj, loggedin => !!auth, title => xml_string sub { obj_ $obj } };
        }
    };
};


sub report_ {
    my($r, $url) = @_;
    my $objid = $r->{object}.(defined $r->{objectnum} ? ".$r->{objectnum}" : '');
    td_ style => 'padding: 3px 5px 5px 20px', sub {
        a_ href => "?id=$r->{id}", "#$r->{id}";
        b_ class => 'grayedout', ' '.fmtdate $r->{date}, 'full';
        txt_ ' by ';
        if($r->{uid}) {
            a_ href => "/$r->{uid}", $r->{username};
            txt_ ' (';
            a_ href => "/t/$r->{uid}/new?title=Regarding your report on $objid&priv=1", 'pm';
            txt_ ')';
        } else {
            txt_ $r->{ip}||'[anonymous]';
        }
        br_;
        obj_ $r;
        br_;
        if($r->{message} && $r->{reason} =~ /spoilers/i) {
            details_ sub {
                summary_ $r->{reason};
                div_ class => 'quote', sub { lit_ bb_format $r->{message} };
            };
        } else {
            txt_ $r->{reason};
            div_ class => 'quote', sub { lit_ bb_format $r->{message} } if $r->{message};
        }
    };
    td_ style => 'width: 300px', sub {
        form_ method => 'post', action => '/report/edit', sub {
            input_ type => 'hidden', name => 'id', value => $r->{id};
            input_ type => 'hidden', name => 'url', value => $url;
            textarea_ name => 'comment', rows => 2, cols => 25, style => 'width: 290px', placeholder => 'Mod comment... (optional)', '';
            br_;
            input_ type => 'submit', class => 'submit', value => 'Post';
            txt_ ' & ';
            input_ type => 'submit', class => 'submit', name => 'status', value => $_, $_ eq $r->{status} ? (style => 'font-weight: bold') : () for @STATUS;
        };
    };
    td_ sub {
        lit_ bb_format $r->{log};
    };
}


TUWF::get qr{/report/list}, sub {
    return tuwf->resDenied if !auth->isMod;

    my $opt = tuwf->validate(get =>
        p      => { upage => 1 },
        s      => { enum => ['id','lastmod'], required => 0, default => 'id' },
        status => { enum => \@STATUS, required => 0 },
        id     => { id => 1, required => 0 },
    )->data;

    my $where = sql_and
        $opt->{id} ? sql 'r.id =', \$opt->{id} : (),
        $opt->{status} ? sql 'r.status =', \$opt->{status} : (),
        $opt->{s} eq 'lastmod' ? 'r.lastmod IS NOT NULL' : ();

    my $cnt = tuwf->dbVali('SELECT count(*) FROM reports r WHERE', $where);
    my $lst = tuwf->dbPagei({results => 25, page => $opt->{p}},
       'SELECT r.id,', sql_totime('r.date'), 'as date, r.uid, ur.username, fmtip(r.ip) as ip, r.reason, r.status, r.message, r.log
             , r.object, r.objectnum, x.title, x.uid as by_uid,', sql_user('uo'), '
          FROM reports r
          LEFT JOIN', item_info('r.object', 'r.objectnum'), 'x ON true
          LEFT JOIN users ur ON ur.id = r.uid
          LEFT JOIN users uo ON uo.id = x.uid
         WHERE', $where, '
         ORDER BY', {id => 'r.id DESC', lastmod => 'r.lastmod DESC'}->{$opt->{s}}
    );

    tuwf->dbExeci(
        'UPDATE users_prefs SET last_reports = NOW()
          WHERE (last_reports IS NULL OR EXISTS(SELECT 1 FROM reports WHERE lastmod > last_reports OR date > last_reports))
            AND id =', \auth->uid
    );

    my sub url { '?'.query_encode %$opt, @_ }

    framework_ title => 'Reports', sub {
        div_ class => 'mainbox', sub {
            h1_ 'Reports';
            p_  'Welcome to the super advanced reports handling interface. Reports can have the following statuses:';
            ul_ sub {
                li_ 'New: Default status for newly submitted reports';
                li_ 'Busy: You can use this state to indicate that you\'re working on it.';
                li_ 'Done: Report handled.';
                li_ 'Dismissed: Report ignored.';
            };
            p_ q{
              There's no flowchart you have to follow, if you can quickly handle a report you can go directly from 'New' to 'Done' or 'Dismissed'.
              If you want to bring an older report to other's attention you can go back from any existing state to 'New'.
            };
            p_ q{
              Feel free to skip over reports that you can't or don't want to handle, someone else will eventually pick it up.
            };
            p_ q{
              Changing the status and/or adding a comment will add an entry to the log, so other mods can see what is going on. Everything on this page is only visible to moderators.
            };
            p_ q{
              BUG: Deleting the last post from a thread (not "hiding", but actually deleting it) will cause the report
              to refer to an innocent post when someone adds a new post to that thread, as the reply will get the same number as the deleted post.
              Not a huge problem, but something to be aware of when browsing through handled reports.
            };
            br_;
            br_;
            p_ class => 'browseopts', sub {
                a_ href => url(p => undef, status => undef), !$opt->{status} ? (class => 'optselected') : (), 'All';
                a_ href => url(p => undef, status => $_), $opt->{status} && $opt->{status} eq $_ ? (class => 'optselected') : (), ucfirst $_ for @STATUS;
            };
            p_ class => 'browseopts', sub {
                txt_ 'Sort by ';
                a_ href => url(p => undef, s => 'id'),      $opt->{s} eq 'id'      ? (class => 'optselected') : (), 'newest';
                a_ href => url(p => undef, s => 'lastmod'), $opt->{s} eq 'lastmod' ? (class => 'optselected') : (), 'last updated';
            };
        };

        paginate_ \&url, $opt->{p}, [$cnt, 25], 't';
        div_ class => 'mainbox thread', sub {
            table_ class => 'stripe', sub {
                my $url = '/report/list'.url;
                tr_ sub { report_ $_, $url } for @$lst;
                tr_ sub { td_ style => 'text-align: center', 'Nothing to report! (heh)' } if !@$lst;
            };
        };
        paginate_ \&url, $opt->{p}, [$cnt, 25], 'b';
    };
};


TUWF::post qr{/report/edit}, sub {
    return tuwf->resDenied if !auth->isMod;
    my $frm = tuwf->validate(post =>
        id      => { id => 1 },
        url     => { regex => qr{^/report/list} },
        status  => { enum => \@STATUS, required => 0 },
        comment => { required => 0, default => '' },
    )->data;
    my $r = tuwf->dbRowi('SELECT id, status FROM reports WHERE id =', \$frm->{id});
    return tuwf->resNotFound if !$r->{id};

    my $log = join '; ',
        $frm->{status} && $r->{status} ne $frm->{status} ? "$r->{status} -> $frm->{status}" : (),
        $frm->{comment} ? $frm->{comment} : ();

    if($log) {
        $log = sprintf "%s <%s> %s\n", fmtdate(time, 'full'), auth->user->{user_name}, $log;
        tuwf->dbExeci('UPDATE reports SET', {
            lastmod => sql('NOW()'),
            $frm->{status} ? (status => $frm->{status}) : (),
            log => sql('log ||', \$log)
        }, 'WHERE id =', \$r->{id});
    }
    tuwf->resRedirect($frm->{url}, 'post');
};

1;
