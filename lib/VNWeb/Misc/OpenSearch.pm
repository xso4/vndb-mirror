package VNWeb::Misc::OpenSearch;

use VNWeb::Prelude;
use TUWF::XML 'xml', 'tag';

TUWF::get qr{/opensearch\.xml}, sub {
    my $h = tuwf->reqBaseURI;
    tuwf->resHeader('Content-Type' => 'application/opensearchdescription+xml');
    xml;
    tag 'OpenSearchDescription', xmlns => 'http://a9.com/-/spec/opensearch/1.1/', 'xmlns:moz' => 'http://www.mozilla.org/2006/browser/search/', sub {
        tag 'ShortName', 'VNDB';
        tag 'LongName', 'VNDB.org Visual Vovel Search';
        tag 'Description', 'Search visual novels on VNDB.org';
        tag 'Image', width => 16, height => 16, type => 'image/x-icon', "$h/favicon.ico";
        tag 'Url', type => 'text/html', method => 'get', template => "$h/v?q={searchTerms}", undef;
        tag 'Url', type => 'application/opensearchdescription+xml', rel => 'self', template => "$h/opensearch.xml", undef;
        tag 'Query', role => 'example', searchTerms => 'Tsukihime', undef;
        tag 'moz:SearchForm', "$h/v";
    }
};

1;
