use v5.36;
use Test::More;
use VNDB::ExtLinks 'extlink_fmt', 'extlink_parse';

no warnings 'qw'; # '#' triggers "Possible attempt to put comments in qw() list"
my @tests = qw{
    scloud     halite_28   - https://soundcloud.com/halite_28

    itch_dev   nuar-games  - https://itch.io/profile/nuar-games
    itch_dev   nuar-games  - https://nuar-games.itch.io/

    itch  rokuth/seasidecollege - https://rokuth.itch.io/seasidecollege/

    wikidata   106518103   - https://www.wikidata.org/wiki/Q106518103
    wikidata   106518103   - https://wikidata.org/wiki/Special:EntityPage/Q106518103#sitelinks-wikipedia

    tumblr     dead-ame    - https://tumblr.com/dead-ame
    tumblr     dead-ame    - https://www.tumblr.com/dead-ame
    tumblr     dead-ame    - https://www.tumblr.com/dead-ame/likes
    tumblr     dead-ame    - https://www.tumblr.com/blog/dead-ame
    tumblr     dead-ame    - https://dead-ame.tumblr.com/

    facebook   100082798702249  - https://www.facebook.com/profile.php?id=100082798702249
    facebook   100082798702249  - https://www.facebook.com/100082798702249
    facebook   YUKIUSAGIdesuno  - https://ja-jp.facebook.com/YUKIUSAGIdesuno
    facebook   Wikipedia   - https://www.facebook.com/Wikipedia/
    facebook   Wikipedia   - https://m.facebook.com/Wikipedia/

    vgmdb_org  1844  - https://vgmdb.net/org/1844

    steam_curator  44693948  - https://store.steampowered.com/curator/44693948

    bilibili  3546811889354850  - https://space.bilibili.com/3546811889354850

    afdian  WoofWoofStudio  - https://www.afdian.com/a/WoofWoofStudio
    afdian  WoofWoofStudio  - https://www.afdian.com/@WoofWoofStudio?ok
    afdian  WX_club         - https://afdian.com/a/WX_club

    weibo   6589791262      - https://www.weibo.com/u/6589791262

    fanbox  renoirzhang     - https://renoirzhang.fanbox.cc/
    fanbox  gurasion        - https://www.fanbox.cc/@gurasion

    steam_curator  29064054  - https://store.steampowered.com/curator/29064054
    steam_curator  29064054  - https://store.steampowered.com/curator/29064054-7DOTS-games/

    playasia 8nt9 12-ji-no-kane-to-cinderella-cinderella-series-triple-pack https://www.play-asia.com/12-ji-no-kane-to-cinderella-cinderella-series-triple-pack/13/708nt9?tagid=969338
    playasia 2623 - https://www.play-asia.com/13/702623

    jastusa srvn068 meteor-world-actor https://jastusa.com/games/srvn068/meteor-world-actor

    dlsite VJ010808 pro    https://www.dlsite.com/pro/work/=/product_id/VJ010808.html
    dlsite RJ151743 maniax https://www.dlsite.com/maniax/dlaf/=/link/work/aid/vndb/id/RJ151743.html
    dlsite RJ151743 maniax https://www.dlsite.com/maniax/work/=/product_id/RJ151743.html/?unique_op=af

    appstore 1071310449 us https://apps.apple.com/us/app/choices-stories-you-play/id1071310449
    appstore 1071310449 -  https://itunes.apple.com/app/id1071310449?ok

    johren dawnofkaguranatsu-ch - https://www.johren.net/games/download/dawnofkaguranatsu-ch/
    johren alphanighthawk-en    - https://www.johren.games/games/download/alphanighthawk-en/

    kagura lessons-with-chii-chan-patch - https://kaguragames.com/lessons-with-chii-chan-patch/

    patreon mircom - https://www.patreon.com/mircom
    patreon mircom - https://www.patreon.com/cw/mircom
};

plan tests => @tests/4*6;

for my ($site, $value, $data, $url) (@tests) {
    $data = '' if $data eq '-';
    my ($psite, $pvalue, $pdata) = extlink_parse $url;
    fail $url if !$psite;
    is $psite, $site, $url;
    is $pvalue, $value, $url;
    is $pdata, $data, $url;

    # Re-formatted URL does not have to match the input but it must survive a round-trip.
    my $nurl = extlink_fmt $site, $value, $data;
    fail "fmt $url" if !$nurl;
    my ($nsite, $nvalue, $ndata) = extlink_parse $nurl;
    is $nsite, $site, "round-trip $url";
    is $nvalue, $value, "round-trip $url";
    is $ndata, $data, "round-trip $url";
}
