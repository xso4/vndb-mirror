package VNWeb::Discussions::Thread;

use VNWeb::Prelude;
use VNWeb::Discussions::Lib;



my $REPLY = form_compile any => {
    tid => { vndbid => 't' },
    old => { anybool => 1 },
    msg => { maxlength => 32768 }
};

js_api DiscussionReply => $REPLY, sub {
    my($data) = @_;
    my $t = tuwf->dbRowi('SELECT id, locked FROM threads t WHERE id =', \$data->{tid}, 'AND', sql_visible_threads());
    return tuwf->resNotFound if !$t->{id};
    return tuwf->resDenied if !can_edit t => $t;

    my $num = sql '(SELECT MAX(num)+1 FROM threads_posts WHERE tid =', \$data->{tid}, ')';
    my $msg = bb_subst_links $data->{msg};
    $num = tuwf->dbVali('INSERT INTO threads_posts', { tid => $t->{id}, num => $num, uid => auth->uid, msg => $msg }, 'RETURNING num');
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
    my $options = tuwf->dbAlli(
        'SELECT tpo.id, tpo.option, count(u.id) as votes, tpm.optid IS NOT NULL as my
           FROM threads_poll_options tpo
           LEFT JOIN threads_poll_votes tpv ON tpv.optid = tpo.id
           LEFT JOIN users u ON tpv.uid = u.id AND NOT u.ign_votes
           LEFT JOIN threads_poll_votes tpm ON tpm.optid = tpo.id AND tpm.uid =', \auth->uid, '
          WHERE tpo.tid =', \$t->{id}, '
          GROUP BY tpo.id, tpo.option, tpm.optid
          ORDER BY tpo.id'
    );
    my $num_votes = tuwf->dbVali(
        'SELECT COUNT(DISTINCT tpv.uid)
          FROM threads_poll_votes tpv
          JOIN threads_poll_options tpo ON tpo.id = tpv.optid
          JOIN users u ON tpv.uid = u.id
         WHERE NOT u.ign_votes AND tpo.tid =', \$t->{id}
    );
    my $preview = $num_votes && (tuwf->reqGet('pollview') || !auth || grep $_->{my}, @$options);
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

    paginate_ \&url, $page, [ $t->{count}, 25 ], 't';
    article_ class => 'thread', id => 'threadstart', sub {
        table_ class => 'stripe', sub {
            tr_ mkclass(deleted => defined $_->{hidden}), id => "p$_->{num}", sub {
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


my $PATH = qr{/$RE{tid}(?:(?<sep>[\./])$RE{num})?};

TUWF::get $PATH, sub {
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

    auth->notiRead($id, [ map $_->{num}, $posts->@* ]) if @$posts;

    framework_ title => $t->{title}, dbobj => $t, $num ? (js => 1, pagevars => {sethash=>"p$num"}) : (), sub {
        metabox_ $t, $posts;
        poll_ $t if $t->{poll_question};
        posts_ $t, $posts, $page;
        reply_ $t, $posts, $page;
    }
};


TUWF::post $PATH, sub {
    my $id = tuwf->capture('id');
    return tuwf->resDenied if !auth || !auth->csrfcheck(tuwf->reqPost('csrf')||'', "poll-$id");

    my $t = tuwf->dbRowi('SELECT poll_question, poll_max_options FROM threads t WHERE id =', \$id, 'AND', sql_visible_threads());
    return tuwf->resNotFound if !$t->{poll_question};

    my %opt = map +($_->{id},1), tuwf->dbAlli('SELECT id FROM threads_poll_options WHERE tid =', \$id)->@*;
    my %vote = map +($_,1), grep $opt{$_}, tuwf->reqPosts('opt');
    my $i = 0;
    my @vote = grep $i++ < $t->{poll_max_options}, sort keys %vote;

    tuwf->dbExeci('DELETE FROM threads_poll_votes WHERE optid IN', [ keys %opt ], 'AND uid =', \auth->uid);
    tuwf->dbExeci('INSERT INTO threads_poll_votes', { uid => auth->uid, optid => $_ }) for @vote;
    tuwf->resRedirect(tuwf->reqPath, 'post');
};

1;
