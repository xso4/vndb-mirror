#!/usr/bin/perl

use v5.28;
use warnings;
use autodie;
use DBI;
use File::Find;

my $GEN = $ENV{VNDB_GEN} // 'gen';
my $imgproc = -f "$GEN/imgproc-custom" ? "$GEN/imgproc-custom" : "$GEN/imgproc";
my $STATIC = ($ENV{VNDB_VAR} // 'var').'/static';
my $ext = qr/\.(?:jpg|webp|png|avif|jxl)/;

my $db = DBI->connect('dbi:Pg:dbname=vndb', 'vndb', undef, { RaiseError => 1, AutoCommit => 1 });

find {
    no_chdir => 1,
    wanted => sub {
        my $orig = $File::Find::name;
        return if $orig !~ /\/([0-9]+)$ext$/;
        my $id = $1;
        my $thumb = $orig =~ s#/cv\.orig/#/cv.t/#r =~ s/$ext$/.jpg/r;
        my $full = $thumb =~ s#/cv\.t/#/cv/#r;
        return if -f $thumb; # already processed

        my $r = `$imgproc size 2>&1 <"$orig"`;
        chomp $r;
        return say "$orig: $r" if $r !~/([0-9]+)x([0-9]+)/;
        my($w,$h) = ($1,$2);
        return if $w <= 256 && $h <= 400;

        $db->do('UPDATE images SET width = ?, height = ? WHERE id = ?', undef, $w, $h, "cv$id");
        rename $full, $thumb;
        `$imgproc jpeg 1 <"$orig" >"$full"`;
        say "$orig: $w $h";
    },
}, "$STATIC/cv.orig";
