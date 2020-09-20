package VNWeb::Reviews::Edit;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;


my $FORM = {
    id      => { vndbid => 'w', required => 0 },
    vid     => { id => 1 },
    vntitle => { _when => 'out' },
    rid     => { id => 1, required => 0 },
    spoiler => { anybool => 1 },
    isfull  => { anybool => 1 },
    text    => { maxlength => 100_000, required => 0, default => '' },
    locked  => { anybool => 1 },

    mod     => { _when => 'out', anybool => 1 },
    releases => { _when => 'out', $VNWeb::Elm::apis{Releases}[0]->%* },
};

my $FORM_IN  = form_compile in  => $FORM;
my $FORM_OUT = form_compile out => $FORM;


sub throttled { tuwf->dbVali('SELECT COUNT(*) FROM reviews WHERE uid =', \auth->uid, 'AND date > date_trunc(\'day\', NOW())') >= 5 }


TUWF::get qr{/$RE{vid}/addreview}, sub {
    my $v = tuwf->dbRowi('SELECT id, title FROM vn WHERE NOT hidden AND id =', \tuwf->capture('id'));
    return tuwf->resNotFound if !$v->{id};

    my $id = tuwf->dbVali('SELECT id FROM reviews WHERE vid =', \$v->{id}, 'AND uid =', \auth->uid);
    return tuwf->resRedirect("/$id/edit") if $id;
    return tuwf->resDenied if !can_edit w => {};

    framework_ title => "Write review for $v->{title}", sub {
        if(throttled) {
            div_ class => 'mainbox', sub {
                h1_ 'Throttled';
                p_ 'You can only submit 5 reviews per day. Check back later!';
            };
        } else {
            elm_ 'Reviews.Edit' => $FORM_OUT, { elm_empty($FORM_OUT)->%*,
                vid => $v->{id}, vntitle => $v->{title}, releases => releases_by_vn($v->{id}), mod => auth->permBoardmod()
            };
        }
    };
};


TUWF::get qr{/$RE{wid}/edit}, sub {
    my $e = tuwf->dbRowi(
        'SELECT r.id, r.uid AS user_id, r.vid, r.rid, r.isfull, r.text, r.spoiler, r.locked, v.title AS vntitle
          FROM reviews r JOIN vn v ON v.id = r.vid WHERE r.id =', \tuwf->capture('id')
    );
    return tuwf->resNotFound if !$e->{id};
    return tuwf->resDenied if !can_edit w => $e;

    $e->{releases} = releases_by_vn $e->{vid};
    $e->{mod} = auth->permBoardmod;
    framework_ title => "Edit review for $e->{vntitle}", type => 'w', dbobj => $e, tab => 'edit', sub {
        elm_ 'Reviews.Edit' => $FORM_OUT, $e;
    };
};



elm_api ReviewsEdit => $FORM_OUT, $FORM_IN, sub {
    my($data) = @_;
    my $id = delete $data->{id};

    my $review = $id ? tuwf->dbRowi('SELECT id, locked, uid AS user_id FROM reviews WHERE id =', \$id) : {};
    return elm_Unauth if !can_edit w => $review;

    $data->{locked} = $review->{locked}||0 if !auth->permBoardmod;

    validate_dbid 'SELECT id FROM vn WHERE id IN', $data->{vid};
    validate_dbid 'SELECT id FROM releases WHERE id IN', $data->{rid} if defined $data->{rid};

    die "Review too long" if !$data->{isfull} && length $data->{text} > 800;
    $data->{text} = bb_subst_links $data->{text} if $data->{isfull};

    if($id) {
        $data->{lastmod} = sql 'NOW()';
        tuwf->dbExeci('UPDATE reviews SET', $data, 'WHERE id =', \$id) if $id;
        auth->audit($review->{user_id}, 'review edit', "edited $review->{id}") if auth->uid != $review->{user_id};

    } else {
        return elm_Unauth if tuwf->dbVali('SELECT 1 FROM reviews WHERE vid =', \$data->{vid}, 'AND uid =', \auth->uid);
        return elm_Unauth if throttled;
        $data->{uid} = auth->uid;
        $id = tuwf->dbVali('INSERT INTO reviews', $data, 'RETURNING id');
    }

    elm_Redirect "/$id"
};


elm_api ReviewsDelete => undef, { id => { vndbid => 'w' } }, sub {
    my($data) = @_;
    my $review = tuwf->dbRowi('SELECT id, uid AS user_id FROM reviews WHERE id =', \$data->{id});
    return elm_Unauth if !can_edit w => $review;
    auth->audit($review->{user_id}, 'review delete', "deleted $review->{id}");
    tuwf->dbExeci('DELETE FROM reviews WHERE id =', \$data->{id});
    elm_Success
};


1;
