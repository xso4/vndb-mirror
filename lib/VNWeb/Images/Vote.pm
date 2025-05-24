package VNWeb::Images::Vote;

use VNWeb::Prelude;
use VNWeb::Images::Lib;


sub can_vote { !config->{read_only} && (auth->permDbmod || (auth->permImgvote && !global_settings->{lockdown_edit})) }


# Fetch a list of images for the user to vote on.
js_api Images => { excl_voted => { anybool => 1 } }, sub($data) {
    fu->denied if !can_vote;

    # This query isn't super fast. Earlier implementations used TABLESAMPLE to
    # pre-select ~5000 candidates if the user has fewer votes than 90% of
    # eligible images, but that's not very effective anymore now that the
    # majority of images are not eligible (c_weight <= 1). That optimization
    # can be brought back by separating out eligible images into a separate
    # table and keeping track of the fraction of those the user has voted on.
    my $l = fu->SQL('
        SELECT id
          FROM images
         WHERE c_weight > 1',
            $data->{excl_voted} ? ('AND', auth->uid, '<> ALL(c_uids)') : (), '
         ORDER BY random() ^ (1.0/c_weight) DESC
         LIMIT 30'
    )->allh;
    # NOTE: JS assumes that, if it receives less than 30 images, we've reached
    # the end of the list and will not attempt to load more.
    enrich_image 1, $l;
    +{ results => $l };
};


js_api ImageVote => {
    votes => { sort_keys => 'id', aoh => {
        id          => { vndbid => [qw/ch cv sf/] },
        token       => {},
        my_sexual   => { uint => 1, range => [0,2] },
        my_violence => { uint => 1, range => [0,2] },
        my_overrule => { anybool => 1 },
    } },
}, sub($data) {
    fu->denied if !can_vote;
    fu->denied if !validate_token $data->{votes};

    # Lock the users table early to prevent deadlock with a concurrent DB edit that attempts to update c_changes.
    fu->sql('SELECT c_imgvotes FROM users WHERE id = $1 FOR UPDATE', auth->uid)->exec;

    # Find out if any of these images are being overruled
    fu->enrich(set => 'overruled', sub { SQL 'SELECT id, bool_or(ignore) FROM image_votes WHERE id', IN $_, 'GROUP BY id' }, $data->{votes});
    fu->enrich(set => 'old_my_overrule', SQL('SELECT id, NOT ignore FROM image_votes WHERE uid =', auth->uid, 'AND id'),
        [ grep $_->{overruled}, $data->{votes}->@* ]
    ) if auth->permDbmod;

    for($data->{votes}->@*) {
        $_->{my_overrule} = 0 if !auth->permDbmod;
        my $d = {
            id       => $_->{id},
            uid      => auth->uid(),
            sexual   => $_->{my_sexual},
            violence => $_->{my_violence},
            ignore   => !$_->{my_overrule} && !$_->{old_my_overrule} && $_->{overruled} ? 1 : 0,
        };
        fu->SQL('INSERT INTO image_votes', VALUES($d), 'ON CONFLICT (id, uid) DO UPDATE', SET($d), ', date = now()')->exec;
        fu->SQL('UPDATE image_votes SET ignore =', $_->{my_overrule}, 'WHERE uid IS DISTINCT FROM', auth->uid, 'AND id =', $_->{id})->exec
            if !$_->{my_overrule} != !$_->{old_my_overrule};
    }

    enrich_image 1, $data->{votes};
    $data->{votes}
};


my $SEND = form_compile {
    images     => { aoh => $IMGSCHEMA },
    single     => { anybool => 1 },
    warn       => { anybool => 1 },
    mod        => { anybool => 1 },
    my_votes   => { uint => 1 },
};


sub imgflag_ {
    article_ widget(ImageFlagging => $SEND, {
        my_votes   => auth ? fu->sql('SELECT c_imgvotes FROM users WHERE id = $1', auth->uid)->val : 0,
        mod        => auth->permDbmod()||0,
        @_
    }), '';
}


FU::get '/img/vote', sub {
    fu->denied if !can_vote;

    my $recent = fu->sql('SELECT id FROM image_votes WHERE uid = $1 ORDER BY date DESC LIMIT 30', auth->uid)->allh;
    enrich_image 1, $recent;

    framework_ title => 'Image flagging', sub {
        imgflag_ images => [ reverse @$recent ], single => 0, warn => 1;
    };
};


FU::get qr{/$RE{imgid}}, sub($id) {
    not_moe;

    my $l = [{ id => $id }];
    enrich_image 0, $l;
    fu->denied if !defined $l->[0]{width};

    framework_ title => "Image flagging for $id", sub {
        imgflag_ images => $l, single => 1, warn => !viewget->{show_nsfw};
    };
};

1;
