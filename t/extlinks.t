#!/usr/bin/perl

use v5.36;
use Test::More;
use VNDB::ExtLinks;

my @tests = qw{
    scloud     halite_28   https://soundcloud.com/halite_28

    itch_dev   nuar-games  https://itch.io/profile/nuar-games
    itch_dev   nuar-games  https://nuar-games.itch.io/
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
