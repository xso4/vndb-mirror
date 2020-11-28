package VNWeb::Releases::Elm;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;


# Used by UList.Opt and CharEdit to fetch releases from a VN id.
elm_api Release => undef, { vid => { id => 1 } }, sub {
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

1;
