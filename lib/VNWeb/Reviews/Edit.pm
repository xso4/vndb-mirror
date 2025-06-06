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


sub throttled { fu->sql('SELECT COUNT(*) FROM reviews WHERE uid = $1 AND date > date_trunc(\'day\', NOW())', auth->uid)->val >= 5 }


FU::get qr{/$RE{vid}/addreview}, sub($vid) {
    my $title = fu->SQL('SELECT title[2] FROM', VNT, 'WHERE NOT hidden AND id =', $vid)->val // fu->notfound;

    my $id = fu->SQL('SELECT id FROM reviews WHERE vid =', $vid, 'AND uid =', auth->uid)->val;
    fu->redirect('temp' => "/$id/edit") if $id;
    fu->denied if !can_edit w => {};

    framework_ title => "Write review for $title", sub {
        if(throttled) {
            article_ sub {
                h1_ 'Throttled';
                p_ 'You can only submit 5 reviews per day. Check back later!';
            };
        } else {
            div_ widget(ReviewEdit => $FORM_OUT, { $FORM_OUT->empty->%*,
                vid => $vid, vntitle => $title, releases => releases_by_vn($vid, released => 1), mod => auth->permBoardmod()
            }), '';
        }
    };
};


FU::get qr{/$RE{wid}/edit}, sub($wid) {
    my $e = fu->SQL(
        'SELECT r.id, r.uid AS user_id, r.vid, r.rid, r.modnote, r.text, r.spoiler, r.locked, v.title[2] AS vntitle
          FROM reviews r JOIN', VNT, 'v ON v.id = r.vid WHERE r.id =', $wid
    )->rowh or fu->notfound;
    fu->denied if !can_edit w => $e;

    $e->{releases} = releases_by_vn $e->{vid}, released => 1;
    $e->{mod} = auth->permBoardmod;
    framework_ title => "Edit review for $e->{vntitle}", dbobj => $e, tab => 'edit', sub {
        div_ widget('ReviewEdit' => $FORM_OUT, $e), '';
    };
};



js_api ReviewEdit => $FORM_IN, sub ($data) {
    my $id = delete $data->{id};

    my $review = $id ? fu->sql('SELECT id, locked, modnote, text, uid AS user_id FROM reviews WHERE id = $1', $id)->rowh // fu->notfound : {};
    fu->denied if !can_edit w => $review;

    if(!auth->permBoardmod) {
        $data->{locked} = $review->{locked}||0;
        $data->{modnote} = $review->{modnote}||'';
    }

    validate_dbid 'SELECT id FROM vn WHERE id', $data->{vid};
    validate_dbid 'SELECT id FROM releases WHERE id', $data->{rid} if defined $data->{rid};

    if($id) {
        $data->{lastmod} = RAW 'NOW()' if $review->{text} ne $data->{text};
        fu->SQL('UPDATE reviews', SET($data), 'WHERE id =', $id)->exec if $id;
        auth->audit($review->{user_id}, 'review edit', "edited $review->{id}") if auth->uid ne $review->{user_id};

    } else {
        return 'You have already submitted a review for this visual novel.'
            if fu->SQL('SELECT 1 FROM reviews WHERE vid =', $data->{vid}, 'AND uid =', auth->uid)->val;
        return 'You may only submit 5 reviews per day.' if throttled;
        $data->{uid} = auth->uid;
        $id = fu->SQL('INSERT INTO reviews', VALUES($data), 'RETURNING id')->val;
    }

    +{ _redir => "/$id".($data->{uid}?'?submit=1':'') };
};


js_api ReviewDelete => { id => { vndbid => 'w' } }, sub ($data) {
    my $review = fu->sql('SELECT id, vid, uid AS user_id FROM reviews WHERE id = $1', $data->{id})->rowh or fu->notfound;
    fu->denied if !can_edit w => $review;
    auth->audit($review->{user_id}, 'review delete', "deleted $review->{id}");
    fu->sql('DELETE FROM notifications WHERE iid = $1', $data->{id})->exec;
    fu->sql('DELETE FROM reviews WHERE id = $1', $data->{id})->exec;
    +{ _redir => "/$review->{vid}" }
};


1;
