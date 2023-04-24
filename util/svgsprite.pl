#!/usr/bin/perl

# Assumptions about the SVG input files:
# - Has a global viewBox that starts at (0,0)
# - At most one <defs>
# - No <style>
# - No xlink (plain 'href' has wide enough support now?)
# - Drawing doesn't extend too far outside its viewbox
#
# I had planned to use fragment identifiers as described in
# https://css-tricks.com/svg-fragment-identifiers-work/
# But it turns out Firefox doesn't cache/reuse the SVG when referenced with
# different fragments. :facepalm:

use v5.26;
use strict;
use autodie;

my %icons = map +(m{([^/]+)\.svg$}, $_), glob('data/icons/*.svg'), glob('data/icons/*/*.svg');
my $idnum = 'a';
my($width, $height) = (-10,0);
my($defs, $group, $css) = ('','','');

for my $id (sort keys %icons) {
    my $data = do { local $/=undef; open my $F, '<', $icons{$id}; <$F> };
    $data =~ s{<\?xml[^>]*>}{};
    $data =~ s{</svg>}{}g;
    $data =~ s{<svg [^>]*viewBox="([^"]+)"[^>]*>}{};
    my $viewbox = $1 // die "No viewBox property found in $icons{$id}\n";
    $data =~ s/\n//g;

    # Identifiers must be globally unique, so need to renumber.
    my %idmap;
    $data =~ s{(id="|href="#|url\(#)([^"\)]+)}{ $idmap{$2}||=$idnum++; $1.$idmap{$2} }eg;

    # Take out the <defs> and put them in global scope, otherwise some(?) renderers can't find the definitions.
    $defs .= $1 if $data =~ s{<defs>(.+)</defs>}{};

    $width += 10;
    $group .= qq{<g transform="translate($width)">$data</g>};
    $css .= ".icons.$id { background-position: -${width}px 0 }\n";

    $width += $viewbox =~ /0 0 ([^ ]+) ([^ ]+)/ && $1 =~ s/^\./0./r;
    $height = $2 if $height < $2;
}

{
    open my $F, '>', 'static/g/svg.css';
    print $F $css;
}

{
    open my $F, '>', 'static/g/icons.svg';
    print $F qq{<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">};
    print $F qq{<defs>$defs</defs>} if $defs;
    print $F $group;
    print $F '</svg>';
}
