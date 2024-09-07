package VNWeb::Releases::Elm;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;


# Used by UList.Opt and CharEdit to fetch releases from a VN id.
elm_api Release => undef, { vid => { vndbid => 'v' } }, sub {
    my($data) = @_;
    elm_Releases releases_by_vn $data->{vid};
};


elm_api Resolutions => undef, {}, sub {
    elm_Resolutions [ map +{ resolution => resolution($_), count => $_->{count} }, tuwf->dbAlli(q{
        SELECT reso_x, reso_y, count(*) AS count FROM releases WHERE NOT hidden AND NOT (reso_x = 0 AND reso_y = 0)
         GROUP BY reso_x, reso_y ORDER BY count(*) DESC
    })->@* ];
};


elm_api Engines => undef, {}, sub {
    elm_Engines tuwf->dbAlli(q{
        SELECT engine, count(*) AS count FROM releases WHERE NOT hidden AND engine <> ''
         GROUP BY engine ORDER BY count(*) DESC, engine
    });
};


elm_api DRM => undef, {}, sub {
    elm_DRM tuwf->dbAlli(q{
        SELECT name, c_ref AS count FROM drm WHERE c_ref > 0 ORDER BY state = 1+1, c_ref DESC, name
    });
};


js_api Release => { vid => { vndbid => 'v' }, charlink => {anybool => 1}, }, sub ($data,@) {
    +{ results => releases_by_vn $data->{vid}, charlink => $data->{charlink} }
};


js_api Resolutions => {}, sub {
    +{ results => [ map +{ id => resolution($_), count => $_->{count} }, tuwf->dbAlli(q{
        SELECT reso_x, reso_y, count(*) AS count FROM releases WHERE NOT hidden AND NOT (reso_x = 0 AND reso_y = 0)
         GROUP BY reso_x, reso_y ORDER BY count(*) DESC
    })->@* ] };
};


js_api Engines => {}, sub {
    +{ results => tuwf->dbAlli(q{
        SELECT engine AS id, count(*) AS count FROM releases WHERE NOT hidden AND engine <> ''
         GROUP BY engine ORDER BY count(*) DESC, engine
    }) };
};


js_api DRM => {}, sub {
    +{ results => tuwf->dbAlli('SELECT name AS id, c_ref AS count, state FROM drm ORDER BY state = 1+1, c_ref DESC, name') };
};

1;
