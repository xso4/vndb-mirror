#!/usr/bin/perl

# This script requires an imagemagick compiled with all image formats supported by imgproc-custom.

use v5.28;
use warnings;
use Cwd 'abs_path';

my $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/test/imgproc-custom\.pl$}{}; }

use lib $ROOT.'/lib';
use VNDB::Func;

my $bin = ($ENV{VNDB_GEN} // 'gen').'/imgproc-custom';

sub cmphash {
    my($fn, $out, $hash) = @_;
    my $outd = `$bin size fit 500 500 jpeg 1 <$fn 2>&1 >tst.jpg`;
    chomp($outd);
    my($hashd) = split / /, `sha1sum tst.jpg`;
    die "Hash mismatch for $fn, got $hashd see tst.jpg\n" if $hash ne $hashd;
    unlink 'tst.jpg';
    die "Output mismatch for $fn, got $outd" if $out ne $outd;
}

sub cmpmagick {
    my($fn, $arg, $size, $hash) = @_;
    `magick -size $size $arg $fn`;
    cmphash $fn, $size, $hash;
    unlink $fn;
}

# Test pngs from http://www.schaik.com/pngsuite/

# These hashes are likely to change with libvips / libjpeg versions, output
# should be manually verified and the hashes updated in that case.
cmphash 'util/test/basn4a08.png', '32x32', '446ceb47d7cfd058a69b0a8f0fcd993489658d2c';
cmphash 'util/test/basn6a16.png', '32x32', 'a4d073bcafd9de6990cb5e723a27e979188cffaa';

# Triggers g_warning() output
die if `$bin size <util/test/xd9n2c08.png 2>&1` !~ /Invalid IHDR data/;
# Triggers vips_error_exit() output
die if `$bin jpeg 5 <util/test/basn4a08.png 2>&1` !~ /write error/;

# Large images are tested to see if extra memory or thread pool use triggers more unique system calls.
# (it does, and yes it varies per input format)
cmpmagick 'large.png', '"canvas:rgb(100,50,30)"', '5000x5000', 'd469c876ca4a737bd0973aaf682b64d524e27602';

cmpmagick 'large-lossless.webp', '"canvas:rgb(100,50,30)" -define webp:lossless=true',  '5000x5000', 'd469c876ca4a737bd0973aaf682b64d524e27602';
cmpmagick 'large-lossy.webp',    '"canvas:rgb(100,50,30)" -define webp:lossless=false', '5000x5000', '6ef162d607c7cfafdf12662e73026a2045a299db';
cmpmagick 'gray.webp', 'pattern:GRAY50 -colorspace GRAY -define webp:lossless=true', '32x32', 'b89eb7012f4c83b51a4949186fbc0647c47eff75';

cmpmagick 'large.jpg', '"canvas:rgb(100,50,30)"', '5000x5000', '6ef162d607c7cfafdf12662e73026a2045a299db';
cmpmagick 'gray.jpg', 'pattern:GRAY50 -colorspace GRAY', '32x32', 'b6f789931d9356470988cdf36154b157824c170e';
cmpmagick 'cmyk.jpg', 'LOGO: -colorspace CMYK', '640x480', 'c7c6de45fe5deae3a7c1c5538c628e1b5d48c3ca'; # Hmm, colors don't seem correct. :/

cmpmagick 'large.avif', '"canvas:rgb(100,50,30)"', '5000x5000', 'c33cebf2bc6cb477726f64762ec40442a28546ce';

cmpmagick 'large.jxl', '"canvas:rgb(100,50,30)"', '5000x5000', '681d4524f780f0f7ecca78d22c103024471d47cc';

# TODO: Test metadata stripping?

# Slow, dumb and somewhat comprehensive thumbnail size checks, it's important
# that the dimensions match with imgsize().
exit; # don't need to test this often
for my $w (10, 50, 256, 400) {
    for my $h (300..1000) {
        `magick -size ${w}x$h 'canvas:rgb(0,0,0)' tst.png`;
        my $dim = `$bin fit 256 300 size <tst.png 2>&1`;
        unlink 'tst.png';
        chomp($dim);
        my $size = join 'x', imgsize $w, $h, 256, 300;
        die "$dim != $size\n" if $dim ne $size;
    }
}
