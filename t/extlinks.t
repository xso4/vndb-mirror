#!/usr/bin/perl

use v5.36;
use Test::More;
use VNDB::ExtLinks;

no warnings 'qw'; # '#' triggers "Possible attempt to put comments in qw() list"
my @tests = qw{
    scloud     halite_28   https://soundcloud.com/halite_28

    itch_dev   nuar-games  https://itch.io/profile/nuar-games
    itch_dev   nuar-games  https://nuar-games.itch.io/

    wikidata   106518103   https://www.wikidata.org/wiki/Q106518103
    wikidata   106518103   https://wikidata.org/wiki/Special:EntityPage/Q106518103#sitelinks-wikipedia

    tumblr     dead-ame    https://tumblr.com/dead-ame
    tumblr     dead-ame    https://www.tumblr.com/dead-ame
    tumblr     dead-ame    https://www.tumblr.com/dead-ame/likes
    tumblr     dead-ame    https://www.tumblr.com/blog/dead-ame
    tumblr     dead-ame    https://dead-ame.tumblr.com/

    facebook   100082798702249  https://www.facebook.com/profile.php?id=100082798702249
    facebook   100082798702249  https://www.facebook.com/100082798702249
    facebook   YUKIUSAGIdesuno  https://ja-jp.facebook.com/YUKIUSAGIdesuno
    facebook   Wikipedia   https://www.facebook.com/Wikipedia/
    facebook   Wikipedia   https://m.facebook.com/Wikipedia/

    vgmdb_org  1844  https://vgmdb.net/org/1844

    steam_curator  44693948  https://store.steampowered.com/curator/44693948

    bilibili  3546811889354850  https://space.bilibili.com/3546811889354850

    afdian  WoofWoofStudio  https://www.afdian.com/a/WoofWoofStudio
    afdian  WoofWoofStudio  https://www.afdian.com/@WoofWoofStudio?ok

    weibo   6589791262      https://www.weibo.com/u/6589791262

    fanbox  renoirzhang     https://renoirzhang.fanbox.cc/
};

plan tests => @tests/3*2;

my $L = \%VNDB::ExtLinks::LINKS;
for my ($site, $value, $url) (@tests) {
    my @f;
    for (keys %$L) {
        if($L->{$_}{full_regex} && $url =~ $L->{$_}{full_regex}) {
            @f = ($_, (grep defined, @{^CAPTURE})[0]);
            last;
        }
    }
    fail $url if !@f;
    is $f[0], $site, $url;
    is $f[1], $value, $url;
}
