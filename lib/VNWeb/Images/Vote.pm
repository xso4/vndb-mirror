package VNWeb::Images::Vote;

use VNWeb::Prelude;
use VNWeb::Images::Lib;


my $SEND = form_compile any => {
    images     => $VNWeb::Elm::apis{ImageResult}[0],
    single     => { anybool => 1 },
    warn       => { anybool => 1 },
    mod        => { anybool => 1 },
    my_votes   => { uint => 1 },
    pWidth     => { uint => 1 }, # Set by JS
    pHeight    => { uint => 1 }, # ^
    nsfw_token => {},
};


sub can_vote { auth->permImgmod || (auth->permImgvote && !global_settings->{lockdown_edit}) }


# Fetch a list of images for the user to vote on.
elm_api Images => $SEND, { excl_voted => { anybool => 1 } }, sub {
    my($data) = @_;
    return elm_Unauth if !can_vote;

    state $stats = tuwf->dbRowi('SELECT COUNT(*) as total, COUNT(*) FILTER (WHERE c_weight > 0) AS referenced FROM images');

    # Performing a proper weighted sampling on the entire images table is way
    # too slow, so we do a TABLESAMPLE to first randomly select a number of
    # rows and then get a weighted sampling from that. The TABLESAMPLE fraction
    # is adjusted so that we get approximately 5000 rows to work with. This is
    # hopefully enough to get a good (weighted) sample and should have a good
    # chance at selecting images even when the user has voted on 90%.
    #
    # TABLESAMPLE is not used if there are only few images to select from, i.e.
    # when the user has already voted on 99% of all images. Finding all
    # applicable images in that case is slow, but at least there aren't many
    # rows for the final ORDER BY.
    my $tablesample =
        !$data->{excl_voted} || tuwf->dbVali('SELECT c_imgvotes FROM users WHERE id =', \auth->uid) < $stats->{referenced}*0.99
        ? 100 * min 1, (5000 / $stats->{referenced}) * ($stats->{total} / $stats->{referenced})
        : 100;

    # NOTE: Elm assumes that, if it receives less than 30 images, we've reached
    # the end of the list and will not attempt to load more.
    my $l = tuwf->dbAlli('
        SELECT id
          FROM images TABLESAMPLE SYSTEM (', \$tablesample, ')
         WHERE c_weight > 0',
            $data->{excl_voted} ? ('AND NOT (c_uids && ARRAY[', \auth->uid, '::vndbid])') : (), '
         ORDER BY random() ^ (1.0/c_weight) DESC
         LIMIT', \30
    );
    warn sprintf 'Weighted random image sampling query returned %d < 30 rows for %s with a sample fraction of %f', scalar @$l, auth->uid(), $tablesample if @$l < 30;
    enrich_image 1, $l;
    elm_ImageResult $l;
};


elm_api ImageVote => undef, {
    votes => { sort_keys => 'id', aoh => {
        id       => { vndbid => [qw/ch cv sf/] },
        token    => {},
        sexual   => { uint => 1, range => [0,2] },
        violence => { uint => 1, range => [0,2] },
        overrule => { anybool => 1 },
    } },
}, sub {
    my($data) = @_;
    return elm_Unauth if !can_vote;
    return elm_CSRF if !validate_token $data->{votes};

    # Find out if any of these images are being overruled
    enrich_merge id => sub { sql 'SELECT id, bool_or(ignore) AS overruled FROM image_votes WHERE id IN', $_, 'GROUP BY id' }, $data->{votes};
    enrich_merge id => sql('SELECT id, NOT ignore AS my_overrule FROM image_votes WHERE uid =', \auth->uid, 'AND id IN'),
        grep $_->{overruled}, $data->{votes}->@* if auth->permImgmod;

    for($data->{votes}->@*) {
        $_->{overrule} = 0 if !auth->permImgmod;
        my $d = {
            id       => $_->{id},
            uid      => auth->uid(),
            sexual   => $_->{sexual},
            violence => $_->{violence},
            ignore   => !$_->{overrule} && !$_->{my_overrule} && $_->{overruled} ? 1 : 0,
        };
        tuwf->dbExeci('INSERT INTO image_votes', $d, 'ON CONFLICT (id, uid) DO UPDATE SET', $d, ', date = now()');
        tuwf->dbExeci('UPDATE image_votes SET ignore =', \($_->{overrule}?1:0), 'WHERE uid IS DISTINCT FROM', \auth->uid, 'AND id =', \$_->{id})
            if !$_->{overrule} != !$_->{my_overrule};
    }
    elm_Success
};


sub my_votes {
    auth ? tuwf->dbVali('SELECT c_imgvotes FROM users WHERE id =', \auth->uid) : 0
}


sub imgflag_ {
    elm_ 'ImageFlagging', $SEND, {
        my_votes   => my_votes(),
        nsfw_token => viewset(show_nsfw => 1),
        mod        => auth->permImgmod()||0,
        @_
    };
}


TUWF::get qr{/img/vote}, sub {
    return tuwf->resDenied if !can_vote;

    my $recent = tuwf->dbAlli('SELECT id FROM image_votes WHERE uid =', \auth->uid, 'ORDER BY date DESC LIMIT', \30);
    enrich_image 1, $recent;

    framework_ title => 'Image flagging', sub {
        imgflag_ images => [ reverse @$recent ], single => 0, warn => 1;
    };
};


TUWF::get qr{/img/$RE{imgid}}, sub {
    my $id = tuwf->capture('id');

    my $l = [{ id => $id }];
    enrich_image auth->permImgmod() || sub { defined $_[0]{my_sexual} }, $l;
    return tuwf->resNotFound if !defined $l->[0]{width};

    framework_ title => "Image flagging for $id", sub {
        imgflag_ images => $l, single => 1, warn => !viewget->{show_nsfw};
    };
};

1;
