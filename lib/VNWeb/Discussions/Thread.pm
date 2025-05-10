package VNWeb::Discussions::Thread;

use VNWeb::Prelude;
use VNWeb::Discussions::Lib;



my $REPLY = form_compile {
    tid => { vndbid => 't' },
    old => { anybool => 1 },
    msg => { maxlength => 32768 }
};

js_api DiscussionReply => $REPLY, sub($data) {
    my $t = fu->SQL(
        'SELECT id, locked FROM threads t WHERE id =', $data->{tid}, 'AND', VISIBLE_THREADS
    )->rowh or fu->notfound;
    fu->denied if !can_edit t => $t;

    my $num = fu->SQL('INSERT INTO threads_posts', VALUES({
        tid => $t->{id},
        num => SQL('(SELECT MAX(num)+1 FROM threads_posts WHERE tid =', $data->{tid}, ')'),
        uid => auth->uid,
        msg => bb_subst_links($data->{msg}),
    }), 'RETURNING num')->val;
    +{ _redir => "/$t->{id}.$num#last" };
};




sub metabox_ {
    my($t, $posts) = @_;
    article_ sub {
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


sub poll_ ($t) {
    my $options = fu->SQL(
        'SELECT tpo.id, tpo.option, count(u.id) as votes, tpm.optid IS NOT NULL as my
           FROM threads_poll_options tpo
           LEFT JOIN threads_poll_votes tpv ON tpv.optid = tpo.id
           LEFT JOIN users u ON tpv.uid = u.id AND NOT u.ign_votes
           LEFT JOIN threads_poll_votes tpm ON tpm.optid = tpo.id AND tpm.uid =', auth->uid, '
          WHERE tpo.tid =', $t->{id}, '
          GROUP BY tpo.id, tpo.option, tpm.optid
          ORDER BY tpo.id'
    )->allh;
    my $num_votes = fu->SQL(
        'SELECT COUNT(DISTINCT tpv.uid)
          FROM threads_poll_votes tpv
          JOIN threads_poll_options tpo ON tpo.id = tpv.optid
          JOIN users u ON tpv.uid = u.id
         WHERE NOT u.ign_votes AND tpo.tid =', $t->{id}
    )->val;
    my $preview = $num_votes && (fu->query(pollview => { anybool => 1 }) || !auth || grep $_->{my}, @$options);
    my $max_votes = max map $_->{votes}, @$options;

    article_ sub {
        h1_ $t->{poll_question};
        form_ method => 'POST', sub {
            input_ type => 'hidden', name => 'csrf', value => auth->csrftoken(0, "poll-$t->{id}") if auth;
            table_ class => 'votebooth', sub {
                thead_ sub { tr_ sub { td_ colspan => 3, sub {
                    em_ sprintf 'You may choose up to %d options', $t->{poll_max_options};
                } } } if $t->{poll_max_options} > 1 && auth;
                tr_ class => $_->{my} ? 'odd' : undef, sub {
                    td_ class => 'tc1', sub { label_ sub {
                        input_ name => "opt", value => $_->{id}, type => $t->{poll_max_options} > 1 ? 'checkbox' : 'radio', checked => $_->{my}?'checked':undef if auth;
                        txt_ " $_->{option}";
                    } };
                    td_ class => 'tc2', sub {
                        div_ style => sprintf('width: %dpx', $_->{votes}/$max_votes*200), '';
                        txt_ " $_->{votes}";
                    } if $preview;
                    td_ class => 'tc3', sprintf '%d%%', $_->{votes} / $num_votes * 100 if $preview;
                } for @$options;
                tfoot_ sub { tr_ sub {
                    td_ class => 'tc1', sub {
                        input_ type => 'submit', value => 'Vote' if auth;
                        small_ 'You must be logged in to vote.' if !auth;
                    };
                    td_ class => 'tc2', sub {
                        em_ 'Nobody voted yet' if !$num_votes;
                        txt_ sprintf '%d vote%s total', $num_votes, $num_votes == 1 ? '' : 's' if $preview && $num_votes;
                        a_ href => '?pollview=1', 'View results' if !$preview && $num_votes;
                    };
                } };
            };
        };
    };
}


# Also used by Reviews::Page for review comments.
sub posts_ {
    my($t, $posts, $page) = @_;
    my sub url { "/$t->{id}".($_?"/$_":'') }

    fu->enrich(key => 'num', aoh => 'patrolled',
        SQL('SELECT p.num,', USER, 'FROM posts_patrolled p JOIN users u ON u.id = p.uid WHERE p.id =', $t->{id}, 'AND p.num'), $posts
    ) if auth->permDbmod;

    paginate_ \&url, $page, [ $t->{count}, 25 ], 't';
    article_ class => 'thread', id => 'threadstart', sub {
        table_ class => 'stripe', sub {
            tr_ class => defined $_->{hidden} ? 'deleted' : undef, id => "p$_->{num}", sub {
                td_ class => 'tc1', $_ == $posts->[$#$posts] ? (id => 'last') : (), sub {
                    a_ href => "/$t->{id}.$_->{num}", "#$_->{num}";
                    if(!defined $_->{hidden} || auth->permBoard) {
                        txt_ ' by ';
                        user_ $_;
                        br_;
                        txt_ fmtdate $_->{date}, 'full';
                    }
                    a_ href => sprintf('/%s.%s?%spatrolled=1', $t->{id}, $_->{num}, (grep $_->{user_id} eq auth->uid, $_->{patrolled}->@*) ? 'un' : ''), sub {
                        txt_ ' ';
                        $_->{patrolled}->@*
                            ? span_ class => 'done', title => "Patrolled by ".join(', ', map user_displayname($_), $_->{patrolled}->@*), '✓'
                            : small_ '#';
                    } if auth->permDbmod;
                };
                td_ class => 'tc2', sub {
                    small_ class => 'edit', sub {
                        txt_ '< ';
                        if(can_edit t => $_) {
                            a_ href => "/$t->{id}".($t->{id} =~ /^w/ || $_->{num} > 1 ? ".$_->{num}" : '').'/edit', 'edit';
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


# Also used by Reviews::Page.
sub mark_patrolled($id, $num) {
    return if !auth->permDbmod;
    my $obj = { id => $id, num => $num, uid => auth->uid };
    fu->SQL('INSERT INTO posts_patrolled', VALUES($obj), 'ON CONFLICT (id,num,uid) DO NOTHING')->exec if fu->query('patrolled');
    fu->SQL('DELETE FROM posts_patrolled', WHERE $obj)->exec if fu->query('unpatrolled');
}


sub reply_ {
    my($t, $posts, $page) = @_;
    return if $t->{count} > $page*25;
    if(can_edit t => $t) {
        div_ widget(DiscussionReply => $REPLY, { tid => $t->{id}, old => $posts->[$#$posts]{date} < time-182*24*3600 }), '';
    } else {
        article_ sub {
            h1_ 'Reply';
            p_ class => 'center',
                    !auth ? 'You must be logged in to reply to this thread.' :
             $t->{locked} ? 'This thread has been locked, you can\'t reply to it anymore.' : 'You can not currently reply to this thread.';
        }
    }
}


my $PATH = qr{/$RE{tid}(?:([\./])($RE{num}))?};

FU::get $PATH, sub($id, $sep='', $num=0) {
    not_moe;
    mark_patrolled $id, $num if $sep eq '.';

    my $t = fu->SQL(
        'SELECT id, title, hidden, locked, private
              , poll_question, poll_max_options
              , (SELECT COUNT(*) FROM threads_posts WHERE tid = id) AS count
           FROM threads t
          WHERE', VISIBLE_THREADS, 'AND id =', $id
    )->rowh or fu->notfound;

    enrich_boards '', [$t];

    my $page = $sep eq '/' ? $num||1 : $sep ne '.' ? 1
        : ceil((fu->SQL('SELECT COUNT(*) FROM threads_posts WHERE num <=', $num, 'AND tid =', $id)->val||9999)/25);
    $num = 0 if $sep ne '.';

    my $posts = fu->SQL(
        'SELECT tp.tid as id, tp.num, tp.hidden, tp.msg,', USER, ', tp.date, tp.edited
           FROM threads_posts tp
           LEFT JOIN users u ON tp.uid = u.id
          WHERE tp.tid =', $id, '
          ORDER BY tp.num
          LIMIT 25 OFFSET', 25*($page-1)
    )->allh;
    fu->notfound if !@$posts || ($num && !grep $_->{num} == $num, @$posts);

    auth->notiRead($id, [ map $_->{num}, $posts->@* ]) if @$posts;

    framework_ title => $t->{title}, dbobj => $t, $num ? (js => 1, pagevars => {sethash=>"p$num"}) : (), sub {
        metabox_ $t, $posts;
        poll_ $t if $t->{poll_question};
        posts_ $t, $posts, $page;
        reply_ $t, $posts, $page;
    }
};


FU::post $PATH, sub($id, @) {
    fu->denied if !auth || !auth->csrfcheck(fu->formdata(csrf => { onerror => '' }), "poll-$id");

    my $t = fu->SQL(
        'SELECT poll_question, poll_max_options FROM threads t WHERE id =', $id, 'AND', VISIBLE_THREADS
    )->rowh || fu->notfound;

    my $opt = fu->sql('SELECT id FROM threads_poll_options WHERE tid = $1', $id)->kvv;
    my %vote = map +($_,1), grep $opt->{$_}, fu->formdata(opt => { default => [], accept_scalar => 1, elems => { uint => 1 } })->@*;
    my $i = 0;
    my @vote = grep $i++ < $t->{poll_max_options}, sort keys %vote;

    fu->SQL('DELETE FROM threads_poll_votes WHERE optid', IN [ keys %$opt ], 'AND uid =', auth->uid)->exec;
    fu->SQL('INSERT INTO threads_poll_votes', VALUES { uid => auth->uid, optid => $_ })->exec for @vote;
    fu->redirect(tempget => fu->path);
};

1;
