package VNWeb::Releases::Engines;

use VNWeb::Prelude;
use VNWeb::AdvSearch;


TUWF::get qr{/r/engines}, sub {
    my $list = tuwf->dbAlli('
        SELECT engine, count(*) AS cnt
          FROM releases
         WHERE NOT hidden AND engine <> \'\'
         GROUP BY engine
         ORDER BY count(*) DESC'
    );

    framework_ title => 'Engine list', sub {
        article_ sub {
            h1_ 'Engine list';
            p_ sub {
                lit_ q{
                 This is a list of all engines currently associated with releases. This
                 list can be used as reference when filling out the engine field for a
                 release and to find inconsistencies in the engine names. See the <a
                 href="/d3#3">releases guidelines</a> for more information.
                };
            };
        };
        article_ class => 'browse', sub {
            table_ class => 'stripe', sub {
                my $c = tuwf->compile({advsearch => 'r'});
                tr_ sub {
                    td_ class => 'tc1', style => 'text-align: right; width: 80px', $_->{cnt};
                    td_ class => 'tc2', sub {
                        a_ href => '/r?f='.$c->validate([engine => '=', $_->{engine}])->data->enc_query(), $_->{engine};
                    }
                } for @$list;
            };
        };
    };
};


1;
