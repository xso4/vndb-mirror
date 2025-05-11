#!/usr/bin/env perl

use v5.36;

my $GEN = $ENV{VNDB_GEN} // 'gen';

my $icons = "$GEN/static/icons.png";
my $ticons = "$GEN/static/icons~.png";
my $css = "$GEN/png.css";
my $imgproc = "$GEN/imgproc";

my @img = map {
    local $/ = undef;
    open my $F, '<', $_ or die $_;
    my $data = <$F>;
    # 8 byte PNG header, 4 byte IHDR chunk length, 4 bytes IHDR chunk identifier, 4 bytes width, 4 bytes height
    my($w,$h) = unpack 'NN', substr $data, 16, 8;
    {
        f => /^icons\/(.+)\.png/ && $1,
        w => $w,
        h => $h,
        d => $data,
    }
} glob("icons/*.png"), glob("icons/*/*.png");


@img = sort { $b->{h} <=> $a->{h} || $b->{w} <=> $a->{w} } @img;


# Simple strip packing algortihm, First-Fit Decreasing Height.
sub genstrip($w) {
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


sub img($w, $h) {
    open my $CMD, "|$imgproc composite >$ticons" or die $!;
    print $CMD pack 'll', $w, $h;
    print $CMD pack('lll', $_->{x}, $_->{y}, length $_->{d}).$_->{d} for @img;
}


sub css {
    open my $F, '>', $css or die $!;
    printf $F ".icon-%s { background-position: %dpx %dpx; width: %dpx; height: %dpx }\n",
        $_->{f} =~ s#/#-#rg, -$_->{x}, -$_->{y}, $_->{w}, $_->{h}
        for @img;
}


img minstrip;
css;
rename $ticons, $icons or die $!;
