package VNWeb::Discussions::Edit;

use VNWeb::Prelude;
use VNWeb::Discussions::Lib;


my $FORM = form_compile any => {
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
        options     => { type => 'array', values => { sl => 1, maxlength => 100 }, minlength => 2, maxlength => 20 },
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
    return tuwf->resDenied if !auth->permBoardmod;
    my $uid = tuwf->dbVali('SELECT uid FROM threads_posts WHERE num = 1 AND tid =', \$data->{id});
    return tuwf->resNotFound if !$uid;
    auth->audit($uid, 'post delete', "deleted $data->{id}.1");
    tuwf->dbExeci('DELETE FROM notifications WHERE iid =', \$data->{id});
    tuwf->dbExeci('DELETE FROM threads WHERE id =', \$data->{id});
    return +{ _redir => '/t' };
};


js_api DiscussionEdit => $FORM, sub ($data) {
    my $tid = $data->{tid};

    my $t = !$tid ? {} : tuwf->dbRowi('
        SELECT t.id, t.poll_question, t.poll_max_options, t.boards_locked, t.hidden, tp.num, tp.uid AS user_id,', sql_totime('tp.date'), 'AS date
          FROM threads t
          JOIN threads_posts tp ON tp.tid = t.id AND tp.num = 1
         WHERE t.id =', \$tid,
          'AND', sql_visible_threads());
    return tuwf->resNotFound if $tid && !$t->{id};
    return tuwf->resDenied if !can_edit t => $t;

    tuwf->dbExeci('DELETE FROM notifications WHERE iid =', \$tid) if $tid && auth->permBoardmod && $data->{hidden};
    auth->audit($t->{user_id}, 'post edit', "edited $tid.1") if $tid && $t->{user_id} ne auth->uid;

    return 'Invalid boards' if !$data->{boards} || grep +(!$BOARD_TYPE{$_->{btype}}{dbitem})^(!$_->{iid}), $data->{boards}->@*;

    validate_dbid 'SELECT id FROM vn        WHERE id IN', map $_->{btype} eq 'v' ? $_->{iid} : (), $data->{boards}->@*;
    validate_dbid 'SELECT id FROM producers WHERE id IN', map $_->{btype} eq 'p' ? $_->{iid} : (), $data->{boards}->@*;
    # Do not validate user boards here, it's possible to have threads assigned to deleted users.

    return 'Invalid max_options' if $data->{poll} && $data->{poll}{max_options} > $data->{poll}{options}->@*;
    my $pollchanged = (!$tid && $data->{poll}) || ($tid && $data->{poll} && (
             $data->{poll}{question} ne ($t->{poll_question}||'')
          || $data->{poll}{max_options} != $t->{poll_max_options}
          || join("\n", $data->{poll}{options}->@*) ne
             join("\n", map $_->{option}, tuwf->dbAlli('SELECT option FROM threads_poll_options WHERE tid =', \$tid, 'ORDER BY id')->@*)
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
    tuwf->dbExeci('UPDATE threads SET', $thread, 'WHERE id =', \$tid) if $tid;
    $tid = tuwf->dbVali('INSERT INTO threads', $thread, 'RETURNING id') if !$tid;

    if(auth->permBoardmod || !$t->{boards_locked}) {
        tuwf->dbExeci('DELETE FROM threads_boards WHERE tid =', \$tid);
        tuwf->dbExeci('INSERT INTO threads_boards', { tid => $tid, type => $_->{btype}, iid => $_->{iid} }) for $data->{boards}->@*;
    }

    if($pollchanged) {
        tuwf->dbExeci('DELETE FROM threads_poll_options WHERE tid =', \$tid);
        tuwf->dbExeci('INSERT INTO threads_poll_options', { tid => $tid, option => $_ }) for $data->{poll}{options}->@*;
    }

    my $post = {
        tid => $tid,
        num => 1,
        msg => bb_subst_links($data->{msg}),
        $data->{tid} ? () : (uid => auth->uid),
        !$data->{tid} || (auth->permBoardmod && $data->{nolastmod}) ? () : (edited => sql 'NOW()')
    };
    tuwf->dbExeci('INSERT INTO threads_posts', $post) if !$data->{tid};
    tuwf->dbExeci('UPDATE threads_posts SET', $post, 'WHERE', { tid => $tid, num => 1 }) if $data->{tid};

    +{ _redir => "/$tid.1" };
};


TUWF::get qr{(?:/t/(?<board>$BOARD_RE)/new|/$RE{tid}\.1/edit)}, sub {
    my $board_id = tuwf->capture('board')||'';
    my($board_type) = $board_id =~ /^([^0-9]+)/;
    $board_id = $board_id =~ /[0-9]$/ ? dbobj $board_id : undef;
    my $tid = tuwf->capture('id');

    return tuwf->resNotFound if $board_id && !$board_id->{id};

    $board_type = 'ge' if $board_type && $board_type eq 'an' && !auth->permBoardmod;

    my $t = !$tid ? {} : tuwf->dbRowi('
        SELECT t.id, tp.tid, t.title, t.locked, t.boards_locked, t.private, t.hidden, t.poll_question, t.poll_max_options, tp.msg, tp.uid AS user_id,', sql_totime('tp.date'), 'AS date
          FROM threads t
          JOIN threads_posts tp ON tp.tid = t.id AND tp.num = 1
         WHERE t.id =', \$tid,
          'AND', sql_visible_threads());
    return tuwf->resNotFound if $tid && !$t->{id};
    return tuwf->resDenied if !can_edit t => $t;

    $t->{poll}{options} = $t->{poll_question} && [ map $_->{option}, tuwf->dbAlli('SELECT option FROM threads_poll_options WHERE tid =', \$t->{id}, 'ORDER BY id')->@* ];
    $t->{poll}{question} = delete $t->{poll_question};
    $t->{poll}{max_options} = delete $t->{poll_max_options};
    $t->{poll} = undef if !$t->{poll}{question};

    if($tid) {
        enrich_boards undef, $t;
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
    $t->{title}   //= tuwf->reqGet('title');
    $t->{tid}     //= undef;
    $t->{private} //= auth->isMod && tuwf->reqGet('priv') ? 1 : 0;
    $t->{locked}  //= 0;
    $t->{boards_locked} //= 0;

    framework_ title => $tid ? 'Edit thread' : 'Create new thread', sub {
        div_ widget('DiscussionEdit' => $FORM, $t), '';
    };
};


1;
