# This script requires an imagemagick compiled with all image formats supported by imgproc-custom.
# Run with VNDB_SLOW_TESTS=1 for a more thourough test.

# Test pngs from http://www.schaik.com/pngsuite/

use v5.36;
use Test::More;
use Digest::SHA;
use VNDB::Func;

my $GEN = $ENV{VNDB_GEN} // 'gen';
my $bin = "$GEN/imgproc-custom";
my $TMP = "$GEN/tmp";

plan skip_all => 'No imgproc-custom binary.' if !-e $bin;
plan skip_all => 'No Imagemagick found.' if !`magick -version 2>/dev/null`;

like `$bin size <t/data/xd9n2c08.png 2>&1`, qr/Invalid IHDR data/, 'g_warning()';
like `$bin jpeg 5 <t/data/basn4a08.png 2>&1`, qr/write error/, 'write error';
is `$bin seccomp-test </dev/null 2>&1`, '', 'seccomp';
is 127 & ($? >> 8), 31, 'SIGSYS';


mkdir $TMP;

sub cmphash {
    my($id, $fn, $out, $hash) = @_;
    my $outd = `$bin size fit 500 500 jpeg 1 <$fn 2>&1 >"$TMP/$id.jpg"`;
    chomp($outd);
    my $hashd = Digest::SHA->new(1)->addfile("$TMP/$id.jpg")->hexdigest;
    is $hashd, $hash, "Hash $fn -> $TMP/$id.jpg";
    is $outd, $out, "Output $fn -> $TMP/$id.jpg";
}

sub cmpmagick {
    my($fn, $arg, $size, $hash) = @_;
    `magick -size $size $arg "$TMP/$fn"`;
    cmphash $fn, "$TMP/$fn", $size, $hash;
}

# These hashes are likely to change with libvips / libjpeg versions, output
# should be manually verified and the hashes updated in that case.
cmphash 'basn4a08', 't/data/basn4a08.png', '32x32', '446ceb47d7cfd058a69b0a8f0fcd993489658d2c';
cmphash 'basn6a16', 't/data/basn6a16.png', '32x32', 'a4d073bcafd9de6990cb5e723a27e979188cffaa';

cmphash 'PCS', 't/data/PCS.png', '536x425', 'eaee84a18edd53194cdc3994a104a71dac4ff016';

# Large images are tested to see if extra memory or thread pool use triggers more unique system calls.
# (it does, and yes it varies per input format)
cmpmagick 'large.png', '"canvas:rgb(100,50,30)"', '5000x5000', 'd469c876ca4a737bd0973aaf682b64d524e27602';

cmpmagick 'large-lossless.webp', '"canvas:rgb(100,50,30)" -define webp:lossless=true',  '5000x5000', 'd469c876ca4a737bd0973aaf682b64d524e27602';
cmpmagick 'large-lossy.webp',    '"canvas:rgb(100,50,30)" -define webp:lossless=false', '5000x5000', '6ef162d607c7cfafdf12662e73026a2045a299db';
cmpmagick 'gray.webp', 'pattern:GRAY50 -colorspace GRAY -define webp:lossless=true', '32x32', 'b89eb7012f4c83b51a4949186fbc0647c47eff75';

cmpmagick 'large.jpg', '"canvas:rgb(100,50,30)"', '5000x5000', '6ef162d607c7cfafdf12662e73026a2045a299db';
cmpmagick 'gray.jpg', 'pattern:GRAY50 -colorspace GRAY', '32x32', 'b6f789931d9356470988cdf36154b157824c170e';
cmpmagick 'cmyk.jpg', 'LOGO: -colorspace CMYK', '640x480', '04b364d87fb7e75196cdc5330cc539b336a53c58'; # Hmm, colors don't seem correct. :/

cmpmagick 'large.avif', '"canvas:rgb(100,50,30)"', '5000x5000', 'c33cebf2bc6cb477726f64762ec40442a28546ce';

cmpmagick 'large.jxl', '"canvas:rgb(100,50,30)"', '5000x5000', '681d4524f780f0f7ecca78d22c103024471d47cc';

# TODO: Test metadata stripping?

# Slow, dumb and somewhat comprehensive thumbnail size checks, it's important
# that the dimensions match with imgsize().
if ($ENV{VNDB_SLOW_TESTS}) {
    for my $w (10, 50, 256, 400) {
        for my $h (300..1000) {
            `magick -size ${w}x$h 'canvas:rgb(0,0,0)' $TMP/tst.png`;
            my $dim = `$bin fit 256 300 size <$TMP/tst.png 2>&1`;
            unlink "$TMP/tst.png";
            chomp($dim);
            my $size = join 'x', imgsize $w, $h, 256, 300;
            is $size, $dim, "imgsize ${w}x$h";
        }
    }
}

done_testing;
