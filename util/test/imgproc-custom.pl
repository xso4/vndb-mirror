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
    `convert -size $size $arg $fn`;
    cmphash $fn, $size, $hash;
    unlink $fn;
}

# Test pngs from http://www.schaik.com/pngsuite/

# These hashes are likely to change with libvips / libjpeg versions, output
# should be manually verified and the hashes updated in that case.
cmphash 'util/test/basn4a08.png', '32x32', '62c4f502c6e8f13fe72cd511267616ea75724503';
cmphash 'util/test/basn6a16.png', '32x32', 'f85f1bb196ad6f8c284370bcb74d5cd8b19fc432';

# Triggers g_warning() output
die if `$bin size <util/test/xd9n2c08.png 2>&1` !~ /Invalid IHDR data/;
# Triggers vips_error_exit() output
die if `$bin jpeg 5 <util/test/basn4a08.png 2>&1` !~ /write error/;

# Large images are tested to see if extra memory or thread pool use triggers more unique system calls.
# (it does, and yes it varies per input format)
cmpmagick 'large.png', '"canvas:rgb(100,50,30)"', '5000x5000', 'c5f1d23d43f3ec42ce04a31ba67334c2b5f68ee2';

cmpmagick 'large-lossless.webp', '"canvas:rgb(100,50,30)" -define webp:lossless=true',  '5000x5000', 'c5f1d23d43f3ec42ce04a31ba67334c2b5f68ee2';
cmpmagick 'large-lossy.webp',    '"canvas:rgb(100,50,30)" -define webp:lossless=false', '5000x5000', 'e043021ad032a8dbfbb21bef373ea9e2851baf51';
cmpmagick 'gray.webp', 'pattern:GRAY50 -colorspace GRAY -define webp:lossless=true', '32x32', '8de7aebd2d86572f9dc320886a3bc4cf59bb53ca';

cmpmagick 'large.jpg', '"canvas:rgb(100,50,30)"', '5000x5000', '7a54b06bdf1b742c5a97f2a105de48da81f3b284';
cmpmagick 'gray.jpg', 'pattern:GRAY50 -colorspace GRAY', '32x32', '13980f3168cdddbe193b445552dab40fa9afa0a1';
cmpmagick 'cmyk.jpg', 'LOGO: -colorspace CMYK', '640x480', '3ff8566e661a0faef5a90d11195819983b595876';

cmpmagick 'large.avif', '"canvas:rgb(100,50,30)"', '5000x5000', 'b42788bf491a9a73d30d58c3a3a843e219f36f91';

cmpmagick 'large.jxl', '"canvas:rgb(100,50,30)"', '5000x5000', 'c5f1d23d43f3ec42ce04a31ba67334c2b5f68ee2';

# TODO: Test metadata stripping?

# Slow, dumb and somewhat comprehensive thumbnail size checks, it's important
# that the dimensions match with imgsize().
exit; # don't need to test this often
for my $w (10, 50, 256, 400) {
    for my $h (300..1000) {
        `convert -size ${w}x$h 'canvas:rgb(0,0,0)' tst.png`;
        my $dim = `$bin fit 256 300 size <tst.png 2>&1`;
        unlink 'tst.png';
        chomp($dim);
        my $size = join 'x', imgsize $w, $h, 256, 300;
        die "$dim != $size\n" if $dim ne $size;
    }
}
