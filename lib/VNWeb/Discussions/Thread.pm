package VNWeb::Discussions::Thread;

use VNWeb::Prelude;
use VNWeb::Discussions::Lib;


my $POLL_OUT = form_compile any => {
    question    => {},
    max_options => { uint => 1 },
    num_votes   => { uint => 1 },
    can_vote    => { anybool => 1 },
    preview     => { anybool => 1 },
    tid         => { vndbid => 't' },
    options     => { aoh => {
        id     => { id => 1 },
        option => {},
        votes  => { uint => 1 },
        my     => { anybool => 1 },
    } },
};

my $POLL_IN = form_compile any => {
    tid     => { vndbid => 't' },
    options => { type => 'array', values => { id => 1 } },
};

elm_api DiscussionsPoll => $POLL_OUT, $POLL_IN, sub {
    my($data) = @_;
    return elm_Unauth if !auth;

    my $t = tuwf->dbRowi('SELECT poll_question, poll_max_options FROM threads t WHERE id =', \$data->{tid}, 'AND', sql_visible_threads());
    return tuwf->resNotFound if !$t->{poll_question};

    die 'Too many options' if $data->{options}->@* > $t->{poll_max_options};
    my %opt = map +($_->{id},1), tuwf->dbAlli('SELECT id FROM threads_poll_options WHERE tid =', \$data->{tid})->@*;
    die 'Invalid option' if grep !$opt{$_}, $data->{options}->@*;

    tuwf->dbExeci('DELETE FROM threads_poll_votes WHERE optid IN', [ keys %opt ], 'AND uid =', \auth->uid);
    tuwf->dbExeci('INSERT INTO threads_poll_votes', { uid => auth->uid, optid => $_ }) for $data->{options}->@*;
    elm_Success
};




my $REPLY = {
    tid => { vndbid => 't' },
    old => { _when => 'out', anybool => 1 },
    msg => { _when => 'in', maxlength => 32768 }
};

my $REPLY_IN  = form_compile in  => $REPLY;
my $REPLY_OUT = form_compile out => $REPLY;

elm_api DiscussionsReply => $REPLY_OUT, $REPLY_IN, sub {
    my($data) = @_;
    my $t = tuwf->dbRowi('SELECT id, locked FROM threads t WHERE id =', \$data->{tid}, 'AND', sql_visible_threads());
    return tuwf->resNotFound if !$t->{id};
    return elm_Unauth if !can_edit t => $t;

    my $num = sql '(SELECT MAX(num)+1 FROM threads_posts WHERE tid =', \$data->{tid}, ')';
    my $msg = bb_subst_links $data->{msg};
    $num = tuwf->dbVali('INSERT INTO threads_posts', { tid => $t->{id}, num => $num, uid => auth->uid, msg => $msg }, 'RETURNING num');
    elm_Redirect "/$t->{id}.$num#last";
};




sub metabox_ {
    my($t, $posts) = @_;
    div_ class => 'mainbox', sub {
        h1_ sub { lit_ bb_format $t->{title}, idonly => 1 };
        # UGLY hack: private threads from Multi (u1) are sometimes (ab)used for system notifications, treat that case differently.
        if ($t->{private} && $posts->[0]{user_id} && $posts->[0]{user_id} eq 'u1') {
            h2_ 'System notification';
            return;
        }
        h2_ 'Hidden' if $t->{hidden};
        h2_ 'Private' if $t->{private};
        h2_ 'Locked' if $t->{locked};
        h2_ 'Posted in';
        ul_ sub {
            li_ sub {
                a_ href => "/t/$_->{btype}", $BOARD_TYPE{$_->{btype}}{txt};
                if($_->{iid}) {
                    txt_ ' > ';
                    a_ style => 'font-weight: bold', href => "/t/$_->{iid}", $_->{iid};
                    txt_ ':';
                    if($_->{title}) {
                        a_ href => "/$_->{iid}", tattr $_;
                    } else {
                        strong_ '[deleted]';
                    }
                }
            } for $t->{boards}->@*;
        };
    }
}


# Also used by Reviews::Page for review comments.
sub posts_ {
    my($t, $posts, $page) = @_;
    my sub url { "/$t->{id}".($_?"/$_":'') }

    paginate_ \&url, $page, [ $t->{count}, 25 ], 't';
    div_ class => 'mainbox thread', id => 'threadstart', sub {
        table_ class => 'stripe', sub {
            tr_ mkclass(deleted => defined $_->{hidden}), id => $_->{num}, sub {
                td_ class => 'tc1', $_ == $posts->[$#$posts] ? (id => 'last') : (), sub {
                    a_ href => "/$t->{id}.$_->{num}", "#$_->{num}";
                    if(!defined $_->{hidden} || auth->permBoard) {
                        txt_ ' by ';
                        user_ $_;
                        br_;
                        txt_ fmtdate $_->{date}, 'full';
                    }
                };
                td_ class => 'tc2', sub {
                    small_ class => 'edit', sub {
                        txt_ '< ';
                        if(can_edit t => $_) {
                            a_ href => "/$t->{id}.$_->{num}/edit", 'edit';
                            txt_ ' - ';
                        }
                        a_ href => "/report/$t->{id}.$_->{num}", 'report';
                        txt_ ' >';
                    } if !defined $_->{hidden} || can_edit t => $_;
                    if(defined $_->{hidden}) {
                        small_ sub {
                            txt_ 'Post deleted';
                            lit_ length $_->{hidden} ? ': '.bb_format $_->{hidden}, inline => 1 : '.';
                        };
                    } else {
                        lit_ bb_format $_->{msg};
                        small_ class => 'lastmod', 'Last modified on '.fmtdate($_->{edited}, 'full') if $_->{edited};
                    }
                };
            } for @$posts;
        };
    };
    paginate_ \&url, $page, [ $t->{count}, 25 ], 'b';
}


sub reply_ {
    my($t, $posts, $page) = @_;
    return if $t->{count} > $page*25;
    if(can_edit t => $t) {
        elm_ 'Discussions.Reply' => $REPLY_OUT, { tid => $t->{id}, old => $posts->[$#$posts]{date} < time-182*24*3600 };
    } else {
        div_ class => 'mainbox', sub {
            h1_ 'Reply';
            p_ class => 'center',
                    !auth ? 'You must be logged in to reply to this thread.' :
             $t->{locked} ? 'This thread has been locked, you can\'t reply to it anymore.' : 'You can not currently reply to this thread.';
        }
    }
}


TUWF::get qr{/$RE{tid}(?:(?<sep>[\./])$RE{num})?}, sub {
    my($id, $sep, $num) = (tuwf->capture('id'), tuwf->capture('sep')||'', tuwf->capture('num'));

    my $t = tuwf->dbRowi(
        'SELECT id, title, hidden, locked, private
              , poll_question, poll_max_options
              , (SELECT COUNT(*) FROM threads_posts WHERE tid = id) AS count
           FROM threads t
          WHERE', sql_visible_threads(), 'AND id =', \$id
    );
    return tuwf->resNotFound if !$t->{id};

    enrich_boards '', $t;

    my $page = $sep eq '/' ? $num||1 : $sep ne '.' ? 1
        : ceil((tuwf->dbVali('SELECT COUNT(*) FROM threads_posts WHERE num <=', \$num, 'AND tid =', \$id)||9999)/25);
    $num = 0 if $sep ne '.';

    my $posts = tuwf->dbPagei({ results => 25, page => $page },
        'SELECT tp.tid as id, tp.num, tp.hidden, tp.msg',
             ',', sql_user(),
             ',', sql_totime('tp.date'), ' as date',
             ',', sql_totime('tp.edited'), ' as edited
           FROM threads_posts tp
           LEFT JOIN users u ON tp.uid = u.id
          WHERE tp.tid =', \$id, '
          ORDER BY tp.num'
    );
    return tuwf->resNotFound if !@$posts || ($num && !grep $_->{num} == $num, @$posts);

    my $poll_options = $t->{poll_question} && tuwf->dbAlli(
        'SELECT tpo.id, tpo.option, count(u.id) as votes, tpm.optid IS NOT NULL as my
           FROM threads_poll_options tpo
           LEFT JOIN threads_poll_votes tpv ON tpv.optid = tpo.id
           LEFT JOIN users u ON tpv.uid = u.id AND NOT u.ign_votes
           LEFT JOIN threads_poll_votes tpm ON tpm.optid = tpo.id AND tpm.uid =', \auth->uid, '
          WHERE tpo.tid =', \$id, '
          GROUP BY tpo.id, tpo.option, tpm.optid
          ORDER BY tpo.id'
    );

    auth->notiRead($id, [ map $_->{num}, $posts->@* ]) if @$posts;

    framework_ title => $t->{title}, dbobj => $t, $num ? (js => 1, pagevars => {sethash=>$num}) : (), sub {
        metabox_ $t, $posts;
        elm_ 'Discussions.Poll' => $POLL_OUT, {
            question    => $t->{poll_question},
            max_options => $t->{poll_max_options},
            num_votes   => tuwf->dbVali(
                'SELECT COUNT(DISTINCT tpv.uid)
                  FROM threads_poll_votes tpv
                  JOIN threads_poll_options tpo ON tpo.id = tpv.optid
                  JOIN users u ON tpv.uid = u.id
                 WHERE NOT u.ign_votes AND tpo.tid =', \$id),
            preview     => !!tuwf->reqGet('pollview'), # Old non-Elm way to preview poll results
            can_vote    => !!auth,
            tid         => $id,
            options     => $poll_options
        } if $t->{poll_question};
        posts_ $t, $posts, $page;
        reply_ $t, $posts, $page;
    }
};

1;
