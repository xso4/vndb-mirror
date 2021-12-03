package VNWeb::Misc::Feeds;

use VNWeb::Prelude;
use FU::XMLWriter 'xml_', 'tag_';


sub datetime { strftime '%Y-%m-%dT%H:%M:%SZ', gmtime shift }


sub feed {
    my($path, $title, $data) = @_;
    my $base = tuwf->reqBaseURI();

    tuwf->resHeader('Content-Type', 'application/atom+xml; charset=UTF-8');
    my $body = xml_ {
        tag_ feed => xmlns => 'http://www.w3.org/2005/Atom', 'xml:lang' => 'en', 'xml:base' => "$base/", sub {
            tag_ title => $title;
            tag_ updated => datetime max grep $_, map +($_->{published}, $_->{updated}), @$data;
            tag_ id => $base.$path;
            tag_ link => rel => 'self', type => 'application/atom+xml', href => $base.tuwf->reqPath(), undef;
            tag_ link => rel => 'alternate', type => 'text/html', href => $base.$path, undef;

            tag_ entry => sub {
                tag_ id => "$base/$_->{id}";
                tag_ title => $_->{title};
                tag_ updated => datetime($_->{updated} || $_->{published});
                tag_ published => datetime $_->{published} if $_->{published};
                tag_ author => sub {
                    tag_ name => $_->{user_name};
                    tag_ uri => "$base/$_->{user_id}";
                } if $_->{user_id};
                tag_ link => rel => 'alternate', type => 'text/html', href => "$base/$_->{id}", undef;
                tag_ summary => type => 'html', bb_format $_->{summary}, maxlength => 300 if $_->{summary};
            } for @$data;
        }
    };
    tuwf->resBinary($body, 'auto');
}


TUWF::get qr{/feeds/announcements.atom}, sub {
    not_moe;
    feed '/t/an', 'VNDB Site Announcements', tuwf->dbAlli('
      SELECT t.id, t.title, tp.msg AS summary
           , ', sql_totime('tp.date'), 'AS published,', sql_totime('tp.edited'), 'AS updated,', sql_user(), '
        FROM threads t
        JOIN threads_posts tp ON tp.tid = t.id AND tp.num = 1
        JOIN threads_boards tb ON tb.tid = t.id AND tb.type = \'an\'
        LEFT JOIN users u ON u.id = tp.uid
       WHERE NOT t.hidden AND NOT t.private
       ORDER BY tb.tid DESC
       LIMIT 10'
    );
};


TUWF::get qr{/feeds/changes.atom}, sub {
    my($lst) = VNWeb::Misc::History::fetch(undef, {m=>1,h=>1,p=>1}, {results=>25});
    for (@$lst) {
        $_->{id}      = "$_->{itemid}.$_->{rev}";
        $_->{title}   = $_->{title}[1];
        $_->{summary} = $_->{comments};
        $_->{updated} = $_->{added};
    }
    feed '/hist', 'VNDB Recent Changes', $lst;
};


TUWF::get qr{/feeds/posts.atom}, sub {
    not_moe;
    feed '/t', 'VNDB Recent Posts', tuwf->dbAlli('
      SELECT t.id||\'.\'||tp.num AS id, t.title||\' (#\'||tp.num||\')\' AS title, tp.msg AS summary
           , ', sql_totime('tp.date'), 'AS published,', sql_totime('tp.edited'), 'AS updated,', sql_user(), '
        FROM threads_posts tp
        JOIN threads t ON t.id = tp.tid
        LEFT JOIN users u ON u.id = tp.uid
       WHERE tp.hidden IS NULL AND NOT t.hidden AND NOT t.private
       ORDER BY tp.date DESC
       LIMIT ', \25
    );
};


1;
