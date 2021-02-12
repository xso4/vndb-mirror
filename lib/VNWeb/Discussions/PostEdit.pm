package VNWeb::Discussions::PostEdit;
# Also used for editing review comments, which follow the exact same format.

use VNWeb::Prelude;
use VNWeb::Discussions::Lib;


my $FORM = {
    id          => { vndbid => ['t','w'] },
    num         => { id => 1 },

    can_mod     => { anybool => 1, _when => 'out' },
    hidden      => { anybool => 1 }, # When can_mod
    nolastmod   => { anybool => 1, _when => 'in' }, # When can_mod
    delete      => { anybool => 1 }, # When can_mod

    msg         => { maxlength => 32768 },
};

my $FORM_OUT = form_compile out => $FORM;
my $FORM_IN  = form_compile in  => $FORM;


sub _info {
    my($id,$num) = @_;
    tuwf->dbRowi('
        SELECT t.id, tp.num, tp.hidden, tp.msg, tp.uid AS user_id,', sql_totime('tp.date'), 'AS date
          FROM threads t
          JOIN threads_posts tp ON tp.tid = t.id AND tp.num =', \$num, '
         WHERE t.id =', \$id, 'AND', sql_visible_threads(),'
       UNION ALL
        SELECT id, num, hidden, msg, uid AS user_id,', sql_totime('date'), 'AS date
          FROM reviews_posts WHERE id =', \$id, 'AND num =', \$num
    );
}


elm_api DiscussionsPostEdit => $FORM_OUT, $FORM_IN, sub {
    my($data) = @_;
    my $id  = $data->{id};
    my $num = $data->{num};

    my $t = _info $id, $num;
    return tuwf->resNotFound if !$t->{id};
    return elm_Unauth if !can_edit t => $t;

    tuwf->dbExeci(q{DELETE FROM notifications WHERE iid =}, \$id, 'AND num =', \$num) if auth->permBoardmod && ($data->{delete} || $data->{hidden});

    if($data->{delete} && auth->permBoardmod) {
        auth->audit($t->{user_id}, 'post delete', "deleted $id.$num");
        tuwf->dbExeci('DELETE FROM threads_posts WHERE tid =', \$id, 'AND num =', \$num);
        tuwf->dbExeci('DELETE FROM reviews_posts WHERE  id =', \$id, 'AND num =', \$num);
        return elm_Redirect "/$id";
    }
    auth->audit($t->{user_id}, 'post edit', "edited $id.$num") if $t->{user_id} ne auth->uid;

    my $post = {
        tid => $id,
        num => $num,
        msg => bb_subst_links($data->{msg}),
        auth->permBoardmod ? (hidden => $data->{hidden}) : (),
        (auth->permBoardmod && $data->{nolastmod}) ? () : (edited => sql 'NOW()')
    };
    tuwf->dbExeci('UPDATE threads_posts SET', $post, 'WHERE', { tid => $id, num => $num });
    $post->{id} = delete $post->{tid};
    tuwf->dbExeci('UPDATE reviews_posts SET', $post, 'WHERE', {  id => $id, num => $num });

    elm_Redirect "/$id.$num";
};


TUWF::get qr{/(?:$RE{tid}|$RE{wid})\.$RE{num}/edit}, sub {
    my($id, $num) = (tuwf->capture('id'), tuwf->capture('num'));
    tuwf->pass if $id =~ /^t/ && $num == 1; # t#.1 goes to Discussions::Edit.

    my $t = _info $id, $num;
    return tuwf->resNotFound if $id && !$t->{id};
    return tuwf->resDenied if !can_edit t => $t;

    $t->{can_mod} = auth->permBoardmod;
    $t->{delete}  = 0;

    framework_ title => 'Edit post', sub {
        elm_ 'Discussions.PostEdit' => $FORM_OUT, $t;
    };
};


1;
