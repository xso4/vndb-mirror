package VNWeb::VN::JS;

use VNWeb::Prelude;


js_api VN => {
    search => { elems => { searchquery => 1 } },
    hidden => { anybool => 1 },
}, sub($data) {
    my @q = grep $_, $data->{search}->@*;
    +{ results => @q ? fu->SQL(
         'SELECT v.id, v.title[2] AS title, v.hidden
           FROM', VNT, 'v', VNWeb::Validate::SearchQuery::JOINA(\@q, 'v', 'v.id'),
          $data->{hidden} ? () : 'WHERE NOT v.hidden', '
          ORDER BY sc.score DESC, v.sorttitle
          LIMIT 50'
    )->allh : [] };
};


js_api VNImageVote => {
    vid => { vndbid => 'v' },
    img => { vndbid => 'cv' },
    vote => { anybool => 1 },
}, sub ($data) {
    fu->denied if !auth;

    my $d = { vid => $data->{vid}, img => $data->{img}, uid => auth->uid };
    fu->SQL('INSERT INTO vn_image_votes', VALUES($d), 'ON CONFLICT (vid, uid, img) DO UPDATE SET date = NOW()')->exec if $data->{vote};
    fu->SQL('DELETE FROM vn_image_votes', WHERE $d)->exec if !$data->{vote};
    fu->sql('SELECT update_vncache($1)', $d->{vid})->exec;
    fu->sql('SELECT update_vn_image_votes($1, $2)', $d->{vid}, $d->{uid})->exec;
    +{}
};


js_api VNCharProducers => { vid => { vndbid => 'v' }}, sub ($data) {
    fu->denied if !auth;
    +{ results => VNWeb::VN::Lib::charproducers($data->{vid}) }
};

1;
