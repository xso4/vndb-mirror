package VNWeb::Discussions::PostEdit;
# Also used for editing review comments, which follow the exact same format.

use VNWeb::Prelude;
use VNWeb::Discussions::Lib;


my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    id          => { vndbid => ['t','w'] },
    num         => { id => 1 },

    can_mod     => { anybool => 1, _when => 'out' },
    hidden      => { default => sub { $_[0] } }, # When can_mod
    nolastmod   => { anybool => 1, _when => 'in' }, # When can_mod
    delete      => { anybool => 1, _when => 'in' }, # When can_mod

    msg         => { maxlength => 32768 },
};


sub _info($id, $num) {
    fu->dbRowi('
        SELECT t.id, tp.num, tp.hidden, tp.msg, tp.uid AS user_id,', sql_totime('tp.date'), 'AS date
          FROM threads t
          JOIN threads_posts tp ON tp.tid = t.id AND tp.num =', \$num, '
         WHERE t.id =', \$id, 'AND', sql_visible_threads(),'
       UNION ALL
        SELECT id, num, hidden, msg, uid AS user_id,', sql_totime('date'), 'AS date
          FROM reviews_posts WHERE id =', \$id, 'AND num =', \$num
    );
}


js_api PostEdit => $FORM_IN, sub ($data) {
    my $id  = $data->{id};
    my $num = $data->{num};

    my $t = _info $id, $num;
    fu->notfound if !$t->{id};
    fu->denied if !can_edit t => $t;

    fu->dbExeci(q{DELETE FROM notifications WHERE iid =}, \$id, 'AND num =', \$num) if auth->permBoardmod && ($data->{delete} || defined $data->{hidden});

    if($data->{delete} && auth->permBoardmod) {
        auth->audit($t->{user_id}, 'post delete', "deleted $id.$num");
        fu->dbExeci('DELETE FROM threads_posts WHERE tid =', \$id, 'AND num =', \$num);
        fu->dbExeci('DELETE FROM reviews_posts WHERE  id =', \$id, 'AND num =', \$num);
        return +{ _redir => "/$id" };
    }
    auth->audit($t->{user_id}, 'post edit', "edited $id.$num") if $t->{user_id} ne auth->uid;

    my $post = {
        tid => $id,
        num => $num,
        msg => bb_subst_links($data->{msg}),
        auth->permBoardmod ? (hidden => $data->{hidden}) : (),
        (auth->permBoardmod && $data->{nolastmod}) ? () : (edited => sql 'NOW()')
    };
    fu->dbExeci('UPDATE threads_posts SET', $post, 'WHERE', { tid => $id, num => $num }) if $id =~ /^t/;
    $post->{id} = delete $post->{tid};
    fu->dbExeci('UPDATE reviews_posts SET', $post, 'WHERE', {  id => $id, num => $num }) if $id =~ /^w/;

    +{ _redir => "/$id.$num" };
};


FU::get qr{/(?:$RE{tid}|$RE{wid})\.($RE{num})/edit}, sub($tid, $wid, $num) {
    fu->redirect(temp => "/$tid/edit") if $tid && $num == 1;
    my $id = $tid || $wid;

    my $t = _info $id, $num;
    fu->notfound if $id && !$t->{id};
    fu->denied if !can_edit t => $t;

    $t->{can_mod} = auth->permBoardmod;
    framework_ title => 'Edit post', sub {
        div_ widget(PostEdit => $FORM_OUT, $t), '';
    };
};


1;
