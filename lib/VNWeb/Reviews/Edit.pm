package VNWeb::Reviews::Edit;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;


my $FORM = {
    id      => { vndbid => 'w', default => undef },
    vid     => { vndbid => 'v' },
    vntitle => { _when => 'out' },
    rid     => { vndbid => 'r', default => undef },
    spoiler => { anybool => 1 },
    isfull  => { anybool => 1 },
    modnote => { maxlength => 1024, default => '' },
    text    => { minlength => 200, maxlength => 100_000, default => '' },
    locked  => { anybool => 1 },

    mod     => { _when => 'out', anybool => 1 },
    releases => { _when => 'out', $VNWeb::Elm::apis{Releases}[0]->%* },
};

my $FORM_IN  = form_compile in  => $FORM;
my $FORM_OUT = form_compile out => $FORM;


sub throttled { tuwf->dbVali('SELECT COUNT(*) FROM reviews WHERE uid =', \auth->uid, 'AND date > date_trunc(\'day\', NOW())') >= 5 }

sub releases {
    my($vid) = @_;
    my $today = strftime '%Y%m%d', gmtime;
    [ grep $_->{released} <= $today, releases_by_vn($vid)->@* ]
}


TUWF::get qr{/$RE{vid}/addreview}, sub {
    my $v = tuwf->dbRowi('SELECT id, title[1+1] FROM', vnt, 'v WHERE NOT hidden AND id =', \tuwf->capture('id'));
    return tuwf->resNotFound if !$v->{id};

    my $id = tuwf->dbVali('SELECT id FROM reviews WHERE vid =', \$v->{id}, 'AND uid =', \auth->uid);
    return tuwf->resRedirect("/$id/edit") if $id;
    return tuwf->resDenied if !can_edit w => {};

    framework_ title => "Write review for $v->{title}", sub {
        if(throttled) {
            article_ sub {
                h1_ 'Throttled';
                p_ 'You can only submit 5 reviews per day. Check back later!';
            };
        } else {
            div_ widget(ReviewEdit => $FORM_OUT, { elm_empty($FORM_OUT)->%*,
                vid => $v->{id}, vntitle => $v->{title}, releases => releases($v->{id}), mod => auth->permBoardmod()
            }), '';
        }
    };
};


TUWF::get qr{/$RE{wid}/edit}, sub {
    my $e = tuwf->dbRowi(
        'SELECT r.id, r.uid AS user_id, r.vid, r.rid, r.isfull, r.modnote, r.text, r.spoiler, r.locked, v.title[1+1] AS vntitle
          FROM reviews r JOIN', vnt, 'v ON v.id = r.vid WHERE r.id =', \tuwf->capture('id')
    );
    return tuwf->resNotFound if !$e->{id};
    return tuwf->resDenied if !can_edit w => $e;

    $e->{releases} = releases $e->{vid};
    $e->{mod} = auth->permBoardmod;
    framework_ title => "Edit review for $e->{vntitle}", dbobj => $e, tab => 'edit', sub {
        div_ widget('ReviewEdit' => $FORM_OUT, $e), '';
    };
};



js_api ReviewEdit => $FORM_IN, sub ($data) {
    my $id = delete $data->{id};

    my $review = $id ? tuwf->dbRowi('SELECT id, locked, modnote, text, uid AS user_id FROM reviews WHERE id =', \$id) : {};
    return tuwf->resNotFound if $id && !$review->{id};
    return tuwf->resDenied if !can_edit w => $review;

    if(!auth->permBoardmod) {
        $data->{locked} = $review->{locked}||0;
        $data->{modnote} = $review->{modnote}||'';
    }

    validate_dbid 'SELECT id FROM vn WHERE id IN', $data->{vid};
    validate_dbid 'SELECT id FROM releases WHERE id IN', $data->{rid} if defined $data->{rid};

    return 'Review too long' if !$data->{isfull} && length $data->{text} > 800;
    $data->{text} = bb_subst_links $data->{text} if $data->{isfull};

    if($id) {
        $data->{lastmod} = sql 'NOW()' if $review->{text} ne $data->{text};
        tuwf->dbExeci('UPDATE reviews SET', $data, 'WHERE id =', \$id) if $id;
        auth->audit($review->{user_id}, 'review edit', "edited $review->{id}") if auth->uid ne $review->{user_id};

    } else {
        return 'You have already submitted a review for this visual novel.'
            if tuwf->dbVali('SELECT 1 FROM reviews WHERE vid =', \$data->{vid}, 'AND uid =', \auth->uid);
        return 'You may only submit 5 reviews per day.' if throttled;
        $data->{uid} = auth->uid;
        $id = tuwf->dbVali('INSERT INTO reviews', $data, 'RETURNING id');
    }

    +{ _redir => "/$id".($data->{uid}?'?submit=1':'') };
};


js_api ReviewDelete => { id => { vndbid => 'w' } }, sub ($data) {
    my $review = tuwf->dbRowi('SELECT id, vid, uid AS user_id FROM reviews WHERE id =', \$data->{id});
    return tuwf->resNotFound if !$review->{id};
    return tuwf->resDenied if !can_edit w => $review;
    auth->audit($review->{user_id}, 'review delete', "deleted $review->{id}");
    tuwf->dbExeci('DELETE FROM notifications WHERE iid =', \$data->{id});
    tuwf->dbExeci('DELETE FROM reviews WHERE id =', \$data->{id});
    +{ _redir => "/$review->{vid}" }
};


1;
