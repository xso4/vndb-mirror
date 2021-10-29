#!/usr/bin/perl

use v5.26;
use warnings;
use Cwd 'abs_path';
use lib ((abs_path $0) =~ s{/\Q$0\E$}{}r).'/lib';

use VNDB::Func 'imgsize', 'imgpath';
use VNDB::Config;
use VNWeb::DB;
use TUWF;

TUWF::set %{ config->{tuwf} };

sub jpgsize {
    my($f) = @_;
    my $id = config->{identify_path};
    return split 'x', `$id -format "%wx%h" "$f"`;

    use bytes;
    open my $F, '<', $f or die "$f: $!";
    die "$f: $!" if 1 > read $F, my $buf, 16*1024;
    die "$f: Not a JPEG\n" if $buf !~ /\xFF[\xC0\xC2]...(....)/s;
    my($h,$w) = unpack 'nn', $1;
    return ($w,$h);
}

for (tuwf->dbAlli('SELECT id, width, height FROM images WHERE id BETWEEN \'sf1\' AND vndbid_max(\'sf\')')->@*) {
    my $fullpath = imgpath $_->{id};
    my $thumbpath = imgpath $_->{id}, 1;
    next if !$_->{width} || !-s $fullpath;
    my ($thumbw, $thumbh) = imgsize $_->{width}, $_->{height}, config->{scr_size}->@*;
    my ($filew, $fileh) = jpgsize $thumbpath;
    if($filew != $thumbw || $fileh != $thumbh) {
        warn "$thumbpath: dimensions don't match, recreating; file=${filew}x$fileh expected=${thumbw}x$thumbh\n";
        my $conv = config->{convert_path};
        my $resize = config->{scr_size}[0].'x'.config->{scr_size}[1].'>';
        unlink 'tmpimg.jpg';
        my ($neww, $newh) = split /x/, `$conv "$fullpath" -strip -quality 90 -resize "$resize" -unsharp 0x0.75+0.75+0.008 -print %wx%h tmpimg.jpg`;
        if(!$neww || !$newh) {
            warn "$thumbpath: unable to write new image\n";
            next;
        }
        if($neww != $thumbw || $newh != $thumbh) {
            warn "$thumbpath: new thumbnail doesn't match expected dimensions, got ${neww}x$newh instead.\n";
            next;
        }
        rename 'tmpimg.jpg', $thumbpath;
    }
}
