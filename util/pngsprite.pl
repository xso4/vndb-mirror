#!/usr/bin/perl

use strict;
use warnings;
use Cwd 'abs_path';

our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/pngsprite\.pl$}{}; }

use lib "$ROOT/lib";
use VNDB::Config;

my $path = "$ROOT/data/icons";
my $icons = "$ROOT/static/g/icons.png";
my $ticons = "$ROOT/static/g/icons~.png";
my $css = "$ROOT/static/g/png.spritecss";

my @img = map {
    my $id = config->{identify_path};
    my($w,$h) = split 'x', `$id -format "%wx%h" "$_"`;
    {
        p => $_,
        f => /^\Q$path\E\/(.+)\.png/ && $1,
        w => $w,
        h => $h,
    }
} glob("$path/*.png"), glob("$path/*/*.png");


@img = sort { $b->{h} <=> $a->{h} || $b->{w} <=> $a->{w} } @img;


# Simple strip packing algortihm, First-Fit Decreasing Height.
sub genstrip {
    my $w = shift;
    my @l;
    my $h = 0;
    for my $i (@img) {
        my $found = 0;
        # @img is assumed to be sorted by height, so image always fits
        # (height-wise) in any of the previously created levels.
        for my $l (@l) {
            next if $l->{left} + $i->{w} > $w;
            # Image fits, add to level
            $i->{x} = $l->{left};
            $i->{y} = $l->{top};
            $l->{left} += $i->{w};
            $found = 1;
            last;
        }
        next if $found;

        # No level found, create a new one
        push @l, { top => $h, left => $i->{w} };
        $i->{x} = 0;
        $i->{y} = $h;
        $h += $i->{h};
    }

    # Recalculate the (actually used) width
    $w = 0;
    $w < $_->{x}+$_->{w} && ($w = $_->{x}+$_->{w}) for (@img);
    ($w, $h);
}


# Tries to find the width of the strip for which the number of unused pixels is
# the minimum. Simple and dumb linear search; it's fast enough.
#
# Note that minimum number of unused pixels does not imply minimum file size,
# although there is some correlation. To further minimize the file size, it's
# possible to attempt to group similar-looking images close together so that
# the final png image might compress better. Finding a good (and fast)
# algorithm for this is not a trivial task, however.
sub minstrip {
    my($minwidth, $maxwidth) = (0,0);
    for(@img) {
        $minwidth = $_->{w} if $_->{w} > $minwidth;
        $maxwidth += $_->{w};
    }

    my($optsize, $w, $h, $optw, $opth) = (1e9, $maxwidth);
    while($w >= $minwidth) {
        ($w, $h) = genstrip($w);
        my $size = $w*$h;
        if($size < $optsize) {
            $optw = $w;
            $opth = $h;
            $optsize = $size;
        }
        $w--;
    }
    genstrip($optw);
}


sub img {
    my($w, $h) = @_;
    my @cmd = (config->{convert_path}, -size => "${w}x$h", 'canvas:rgba(0,0,0,0)',
        map(+($_->{p}, -geometry => "+$_->{x}+$_->{y}", '-composite'), @img),
        '-strip', "png32:$ticons"
    );
    system(@cmd);
}


sub css {
    # The gender icons need special treatment, they're 3 icons in one image.
    my $gender;

    open my $F, '>', $css or die $!;
    for my $i (@img) {
        if($i->{f} eq 'gender') {
            $gender = $i;
            next;
        }
        printf $F ".icon-%s { background-position: %dpx %dpx; width: %dpx; height: %dpx }\n", $i->{f} =~ s#/#-#rg, -$i->{x}, -$i->{y}, $i->{w}, $i->{h};
    }
    printf $F ".icon-gen-f, .icon-gen-b { background-position: %dpx %dpx; width: 14px; height: 14px }\n", -$gender->{x}, -$gender->{y};
    print  $F ".icon-gen-b { width: 28px }\n";
    printf $F ".icon-gen-m { background-position: %dpx %dpx; width: 14px; height: 14px }\n", -($gender->{x}+14), -$gender->{y};
}


img minstrip;
css;
rename $ticons, $icons or die $!;
