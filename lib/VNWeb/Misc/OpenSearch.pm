package VNWeb::Misc::OpenSearch;

use VNWeb::Prelude;
use FU::XMLWriter 'xml_', 'tag_';

FU::get '/opensearch.xml', sub {
    my $h = config->{url};
    state $xml = xml_ {
        tag_ 'OpenSearchDescription', xmlns => 'http://a9.com/-/spec/opensearch/1.1/', 'xmlns:moz' => 'http://www.mozilla.org/2006/browser/search/', sub {
            tag_ 'ShortName', 'VNDB';
            tag_ 'LongName', 'VNDB.org Visual Vovel Search';
            tag_ 'Description', 'Search visual novels on VNDB.org';
            tag_ 'Image', width => 16, height => 16, type => 'image/x-icon', "$h/favicon.ico";
            tag_ 'Url', type => 'text/html', method => 'get', template => "$h/v?q={searchTerms}", undef;
            tag_ 'Url', type => 'application/opensearchdescription+xml', rel => 'self', template => "$h/opensearch.xml", undef;
            tag_ 'Query', role => 'example', searchTerms => 'Tsukihime', undef;
            tag_ 'moz:SearchForm', "$h/v";
        }
    };
    fu->set_header('content-type' => 'application/opensearchdescription+xml');
    fu->set_body($xml);
};

1;
