package VNWeb::Discussions::Edit;

use VNWeb::Prelude;
use VNWeb::Discussions::Lib;


my $FORM = form_compile {
    tid    => { default => undef, vndbid => 't' },
    title  => { sl => 1, maxlength => 50 },
    msg    => { maxlength => 32768 },
    boards => { default => undef, sort_keys => [ 'btype', 'iid' ], aoh => {
        id    => {},
        btype => {},
        iid   => { default => undef, vndbid => [qw/u v p/] },
        title => { default => undef },
    } },
    poll   => { default => undef, type => 'hash', keys => {
        question    => { sl => 1, maxlength => 100 },
        max_options => { uint => 1, min => 1, max => 20 },
        options     => { elems => { sl => 1, maxlength => 100 }, minlength => 2, maxlength => 20 },
    } },

    can_mod       => { anybool => 1 },
    can_private   => { anybool => 1 },
    locked        => { anybool => 1 }, # When can_mod
    hidden        => { anybool => 1 }, # When can_mod
    boards_locked => { anybool => 1 }, # When can_mod
    private       => { anybool => 1 }, # When can_private
    nolastmod     => { anybool => 1 }, # When can_mod
};


js_api DiscussionDelete => { id => { vndbid => 't' } }, sub ($data) {
    fu->denied if !auth->permBoardmod;
    my $uid = fu->sql('SELECT uid FROM threads_posts WHERE num = 1 AND tid = $1', $data->{id})->val or fu->notfound;
    auth->audit($uid, 'post delete', "deleted $data->{id}.1");
    fu->sql('DELETE FROM notifications WHERE iid = $1', $data->{id})->exec;
    fu->sql('DELETE FROM threads WHERE id = $1', $data->{id})->exec;
    return +{ _redir => '/t' };
};


js_api DiscussionEdit => $FORM, sub ($data) {
    my $tid = $data->{tid};

    my $t = !$tid ? {} : fu->SQL('
        SELECT t.id, t.poll_question, t.poll_max_options, t.boards_locked, t.hidden, tp.num, tp.uid AS user_id, tp.date
          FROM threads t
          JOIN threads_posts tp ON tp.tid = t.id AND tp.num = 1
         WHERE t.id =', $tid, 'AND', VISIBLE_THREADS
    )->rowh;
    fu->notfound if $tid && !$t->{id};
    fu->denied if !can_edit t => $t;

    fu->sql('DELETE FROM notifications WHERE iid = $1', $tid)->exec if $tid && auth->permBoardmod && $data->{hidden};
    auth->audit($t->{user_id}, 'post edit', "edited $tid.1") if $tid && $t->{user_id} ne auth->uid;

    return 'Invalid boards' if !$data->{boards} || grep +(!$BOARD_TYPE{$_->{btype}}{dbitem})^(!$_->{iid}), $data->{boards}->@*;

    validate_dbid 'SELECT id FROM vn        WHERE id', map $_->{btype} eq 'v' ? $_->{iid} : (), $data->{boards}->@*;
    validate_dbid 'SELECT id FROM producers WHERE id', map $_->{btype} eq 'p' ? $_->{iid} : (), $data->{boards}->@*;
    # Do not validate user boards here, it's possible to have threads assigned to deleted users.

    return 'Invalid max_options' if $data->{poll} && $data->{poll}{max_options} > $data->{poll}{options}->@*;
    my $pollchanged = (!$tid && $data->{poll}) || ($tid && $data->{poll} && (
             $data->{poll}{question} ne ($t->{poll_question}||'')
          || $data->{poll}{max_options} != $t->{poll_max_options}
          || join("\n", $data->{poll}{options}->@*) ne
             join("\n", fu->SQL('SELECT option FROM threads_poll_options WHERE tid =', $tid, 'ORDER BY id')->flat->@*)
    ));

    my $thread = {
        title            => $data->{title},
        poll_question    => $data->{poll} ? $data->{poll}{question} : undef,
        poll_max_options => $data->{poll} ? $data->{poll}{max_options} : 1,
        auth->permBoardmod ? (
            hidden => $data->{hidden},
            locked => $data->{locked},
            boards_locked => $data->{boards_locked},
        ) : (),
        auth->isMod ? (
            private => $data->{private}
        ) : (),
    };
    fu->SQL('UPDATE threads', SET($thread), 'WHERE id =', $tid)->exec if $tid;
    $tid = fu->SQL('INSERT INTO threads', VALUES($thread), 'RETURNING id')->val if !$tid;

    if(auth->permBoardmod || !$t->{boards_locked}) {
        fu->SQL('DELETE FROM threads_boards WHERE tid =', $tid)->exec;
        fu->SQL('INSERT INTO threads_boards', VALUES { tid => $tid, type => $_->{btype}, iid => $_->{iid} })->exec for $data->{boards}->@*;
    }

    if($pollchanged) {
        fu->SQL('DELETE FROM threads_poll_options WHERE tid =', $tid)->exec;
        fu->SQL('INSERT INTO threads_poll_options', VALUES { tid => $tid, option => $_ })->exec for $data->{poll}{options}->@*;
    }

    my $post = {
        tid => $tid,
        num => 1,
        msg => bb_subst_links($data->{msg}),
        $data->{tid} ? () : (uid => auth->uid),
        !$data->{tid} || (auth->permBoardmod && $data->{nolastmod}) ? () : (edited => SQL 'NOW()')
    };
    fu->SQL('INSERT INTO threads_posts', VALUES $post)->exec if !$data->{tid};
    fu->SQL('UPDATE threads_posts', SET($post), WHERE { tid => $tid, num => 1 })->exec if $data->{tid};
    notify_mentions $tid, 1, $data->{msg} if !$thread->{hidden} && !$thread->{locked};

    +{ _redir => "/$tid.1" };
};


FU::get qr{(?:/t/($BOARD_RE)/new|/$RE{tid}/edit)}, sub($board_id,$tid=undef) {
    $board_id //= '';
    my($board_type) = $board_id =~ /^([^0-9]+)/;
    $board_id = $board_id =~ /[0-9]$/ ? dbobj $board_id : undef;

    fu->notfound if $board_id && !$board_id->{id};

    $board_type = 'ge' if $board_type && $board_type eq 'an' && !auth->permBoardmod;

    my $t = !$tid ? {} : fu->SQL('
        SELECT t.id, tp.tid, t.title, t.locked, t.boards_locked, t.private, t.hidden, t.poll_question, t.poll_max_options, tp.msg, tp.uid AS user_id, tp.date
          FROM threads t
          JOIN threads_posts tp ON tp.tid = t.id AND tp.num = 1
         WHERE t.id =', $tid, 'AND', VISIBLE_THREADS
    )->rowh;
    fu->notfound if $tid && !$t->{id};
    fu->denied if !can_edit t => $t;

    $t->{poll}{options} = $t->{poll_question} && fu->SQL('SELECT option FROM threads_poll_options WHERE tid =', $t->{id}, 'ORDER BY id')->flat;
    $t->{poll}{question} = delete $t->{poll_question};
    $t->{poll}{max_options} = delete $t->{poll_max_options};
    $t->{poll} = undef if !$t->{poll}{question};

    if($tid) {
        enrich_boards undef, [$t];
    } else {
        $t->{boards} = [ {
            id    => $board_id ? $board_id->{id} : $board_type,
            btype => $board_type,
            iid   => $board_id ? $board_id->{id} : undef,
            title => $board_id ? $board_id->{title} : undef,
        } ];
        push $t->{boards}->@*, { id => auth->uid, btype => 'u', iid => auth->uid, title => [undef,auth->user->{user_name}] }
            if $board_type eq 'u' && $board_id->{id} ne auth->uid;
    }
    $_->{title} = $_->{title} && $_->{title}[1] for $t->{boards}->@*;

    $t->{can_mod}     = auth->permBoardmod;
    $t->{can_private} = auth->isMod;

    $t->{hidden}  //= 0;
    $t->{msg}     //= '';
    $t->{title}   //= fu->query(title => { onerror => ''});
    $t->{tid}     //= undef;
    $t->{private} //= auth->isMod && fu->query(priv => { anybool => 1 }),
    $t->{locked}  //= 0;
    $t->{boards_locked} //= 0;

    framework_ title => $tid ? 'Edit thread' : 'Create new thread', sub {
        div_ widget('DiscussionEdit' => $FORM, $t), '';
    };
};


1;
