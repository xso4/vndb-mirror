package VNWeb::Releases::JS;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;

js_api Release => { vid => { vndbid => 'v' }, charlink => {anybool => 1}, }, sub ($data,@) {
    +{ results => releases_by_vn $data->{vid}, charlink => $data->{charlink} }
};


js_api Resolutions => {}, sub {
    +{ results => [ map +{ id => resolution($_), count => $_->{count} }, fu->sql(q{
        SELECT reso_x, reso_y, count(*) AS count FROM releases WHERE NOT hidden AND NOT (reso_x = 0 AND reso_y = 0)
         GROUP BY reso_x, reso_y ORDER BY count(*) DESC
    })->allh->@* ] };
};


js_api Engines => {}, sub {
    +{ results => fu->sql(q{
        SELECT engine AS id, count(*) AS count FROM releases WHERE NOT hidden AND engine <> ''
         GROUP BY engine ORDER BY count(*) DESC, engine
    })->allh };
};


js_api DRM => {}, sub {
    +{ results => fu->sql('SELECT name AS id, c_ref AS count, state FROM drm ORDER BY state = 2, c_ref DESC, name')->allh };
};

1;
