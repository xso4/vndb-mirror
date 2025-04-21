package VNWeb::Reviews::Edit;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;


my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    id      => { vndbid => 'w', default => undef },
    vid     => { vndbid => 'v' },
    vntitle => { _when => 'out' },
    rid     => { vndbid => 'r', default => undef },
    spoiler => { anybool => 1 },
    modnote => { maxlength => 1024, default => '' },
    text    => { minlength => 200, maxlength => 100_000, default => '' },
    locked  => { anybool => 1 },

    mod     => { _when => 'out', anybool => 1 },
    releases => { _when => 'out', aoh => $RELSCHEMA },
};


sub throttled { fu->dbVali('SELECT COUNT(*) FROM reviews WHERE uid =', \auth->uid, 'AND date > date_trunc(\'day\', NOW())') >= 5 }

sub releases {
    my($vid) = @_;
    my $today = strftime '%Y%m%d', gmtime;
    [ grep $_->{released} <= $today, releases_by_vn($vid)->@* ]
}


FU::get qr{/$RE{vid}/addreview}, sub($vid) {
    my $v = fu->dbRowi('SELECT id, title[1+1] FROM', vnt, 'v WHERE NOT hidden AND id =', \$vid);
    fu->notfound if !$v->{id};

    my $id = fu->dbVali('SELECT id FROM reviews WHERE vid =', \$v->{id}, 'AND uid =', \auth->uid);
    fu->redirect('temp' => "/$id/edit") if $id;
    fu->renied if !can_edit w => {};

    framework_ title => "Write review for $v->{title}", sub {
        if(throttled) {
            article_ sub {
                h1_ 'Throttled';
                p_ 'You can only submit 5 reviews per day. Check back later!';
            };
        } else {
            div_ widget(ReviewEdit => $FORM_OUT, { $FORM_OUT->empty->%*,
                vid => $v->{id}, vntitle => $v->{title}, releases => releases($v->{id}), mod => auth->permBoardmod()
            }), '';
        }
    };
};


FU::get qr{/$RE{wid}/edit}, sub($wid) {
    my $e = fu->dbRowi(
        'SELECT r.id, r.uid AS user_id, r.vid, r.rid, r.modnote, r.text, r.spoiler, r.locked, v.title[1+1] AS vntitle
          FROM reviews r JOIN', vnt, 'v ON v.id = r.vid WHERE r.id =', \$wid
    );
    fu->notfound if !$e->{id};
    fu->denied if !can_edit w => $e;

    $e->{releases} = releases $e->{vid};
    $e->{mod} = auth->permBoardmod;
    framework_ title => "Edit review for $e->{vntitle}", dbobj => $e, tab => 'edit', sub {
        div_ widget('ReviewEdit' => $FORM_OUT, $e), '';
    };
};



js_api ReviewEdit => $FORM_IN, sub ($data) {
    my $id = delete $data->{id};

    my $review = $id ? fu->dbRowi('SELECT id, locked, modnote, text, uid AS user_id FROM reviews WHERE id =', \$id) : {};
    fu->notfound if $id && !$review->{id};
    fu->denied if !can_edit w => $review;

    if(!auth->permBoardmod) {
        $data->{locked} = $review->{locked}||0;
        $data->{modnote} = $review->{modnote}||'';
    }

    validate_dbid 'SELECT id FROM vn WHERE id IN', $data->{vid};
    validate_dbid 'SELECT id FROM releases WHERE id IN', $data->{rid} if defined $data->{rid};

    if($id) {
        $data->{lastmod} = sql 'NOW()' if $review->{text} ne $data->{text};
        fu->dbExeci('UPDATE reviews SET', $data, 'WHERE id =', \$id) if $id;
        auth->audit($review->{user_id}, 'review edit', "edited $review->{id}") if auth->uid ne $review->{user_id};

    } else {
        return 'You have already submitted a review for this visual novel.'
            if fu->dbVali('SELECT 1 FROM reviews WHERE vid =', \$data->{vid}, 'AND uid =', \auth->uid);
        return 'You may only submit 5 reviews per day.' if throttled;
        $data->{uid} = auth->uid;
        $id = fu->dbVali('INSERT INTO reviews', $data, 'RETURNING id');
    }

    +{ _redir => "/$id".($data->{uid}?'?submit=1':'') };
};


js_api ReviewDelete => { id => { vndbid => 'w' } }, sub ($data) {
    my $review = fu->dbRowi('SELECT id, vid, uid AS user_id FROM reviews WHERE id =', \$data->{id});
    fu->notfound if !$review->{id};
    fu->denied if !can_edit w => $review;
    auth->audit($review->{user_id}, 'review delete', "deleted $review->{id}");
    fu->dbExeci('DELETE FROM notifications WHERE iid =', \$data->{id});
    fu->dbExeci('DELETE FROM reviews WHERE id =', \$data->{id});
    +{ _redir => "/$review->{vid}" }
};


1;
