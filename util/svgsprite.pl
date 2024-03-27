#!/usr/bin/perl

# I had planned to use fragment identifiers as described in
# https://css-tricks.com/svg-fragment-identifiers-work/
# But it turns out Firefox doesn't cache/reuse the SVG when referenced with
# different fragments. :facepalm:

use v5.26;
use strict;
use autodie;

my $GEN = $ENV{VNDB_GEN} // 'gen';

my %icons = map +((m{^icons/(.+)\.svg$})[0] =~ s#/#-#rg, $_), glob('icons/*.svg'), glob('icons/*/*.svg');
my $idnum = 'a';
my($width, $height) = (-10,0);
my($defs, $group, $css) = ('','','');

for my $id (sort keys %icons) {
    my $data = do { local $/=undef; open my $F, '<', $icons{$id}; <$F> };
    $data =~ s{<\?xml[^>]*>}{};
    $data =~ s{</svg>}{}g;
    $data =~ s/\n//g;
    $data =~ s{<svg [^>]*viewBox="0 0 ([^ ]+) ([^ ]+)"[^>]*>}{};
    my($w,$h) = ($1,$2);
    my $viewbox = $w // die "No suitable viewBox property found in $icons{$id}\n";

    # Identifiers must be globally unique, so need to renumber.
    my %idmap;
    $data =~ s{(id="|href="#|url\(#)([^"\)]+)}{ $idmap{$2}||=$idnum++; $1.$idmap{$2} }eg;

    # Take out the <defs> and put them in global scope, otherwise some(?) renderers can't find the definitions.
    $defs .= $1 if $data =~ s{<defs>(.+)</defs>}{};

    $width += 10;
    $group .= qq{<g transform="translate($width)">$data</g>};
    $css .= sprintf ".icon-%s { background-position: %dpx 0; width: %dpx; height: %dpx }\n", $id, -$width, $w, $h;

    $width += $w;
    $height = $h if $height < $h;
}

{
    open my $F, '>', "$GEN/svg.css";
    print $F $css;
}

{
    open my $F, '>', "$GEN/static/icons.svg";
    print $F qq{<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">};
    print $F qq{<defs>$defs</defs>} if $defs;
    print $F $group;
    print $F '</svg>';
}
