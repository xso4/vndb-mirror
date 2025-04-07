#!/usr/bin/perl

# This script finds all unused and unreferenced images in var/static/ and
# outputs a shell script to remove them.
#
# Use with care!

use v5.36;
use FU::Pg;
use File::Find;

$ENV{VNDB_VAR} //= 'var';

my $db = FU::Pg->connect('dbname=vndb user=vndb');

my $dirmatch = '/(cv|ch|sf|st)(?:\.orig|\.t)?/';
my $fnmatch = $dirmatch.'[0-9][0-9]/([1-9][0-9]{0,6})\.(?:jpg|webp|png|avif|jxl)?';


sub cleandb {
    # Delete all images from the `images` table that are not referenced from
    # *anywhere* in the database, including old revisions and links found in
    # comments, descriptions and docs.
    # The 30 (100, in the case of screenshots) most recently uploaded images of
    # each type are also kept because there's a good chance they will get
    # referenced from somewhere, soon.
    my $cnt = $db->exec(q{
      DELETE FROM images WHERE id IN(
        SELECT id FROM images
         WHERE id NOT IN(SELECT id FROM images WHERE id ^= 'ch' ORDER BY id DESC LIMIT  30)
           AND id NOT IN(SELECT id FROM images WHERE id ^= 'cv' ORDER BY id DESC LIMIT  30)
           AND id NOT IN(SELECT id FROM images WHERE id ^= 'sf' ORDER BY id DESC LIMIT 100)
        EXCEPT
        SELECT * FROM (
                SELECT scr   FROM vn_screenshots
          UNION SELECT scr   FROM vn_screenshots_hist
          UNION SELECT img   FROM releases_images
          UNION SELECT img   FROM releases_images_hist
          UNION SELECT image FROM vn         WHERE image IS NOT NULL
          UNION SELECT image FROM vn_hist    WHERE image IS NOT NULL
          UNION SELECT image FROM chars      WHERE image IS NOT NULL
          UNION SELECT image FROM chars_hist WHERE image IS NOT NULL
          UNION (
            SELECT vndbid(case when img[1] = 'st' then 'sf' else img[1] end::vndbtag, img[2]::int)
              FROM (      SELECT content FROM docs
                UNION ALL SELECT content FROM docs_hist
                UNION ALL SELECT description FROM vn
                UNION ALL SELECT description FROM vn_hist
                UNION ALL SELECT description FROM chars
                UNION ALL SELECT description FROM chars_hist
                UNION ALL SELECT description FROM producers
                UNION ALL SELECT description FROM producers_hist
                UNION ALL SELECT notes  FROM releases
                UNION ALL SELECT notes  FROM releases_hist
                UNION ALL SELECT description FROM staff
                UNION ALL SELECT description FROM staff_hist
                UNION ALL SELECT description FROM tags
                UNION ALL SELECT description FROM tags_hist
                UNION ALL SELECT description FROM traits
                UNION ALL SELECT description FROM traits_hist
                UNION ALL SELECT comments FROM changes
                UNION ALL SELECT msg FROM threads_posts
                UNION ALL SELECT msg FROM reviews_posts
                UNION ALL SELECT text FROM reviews
              ) x(text), regexp_matches(text, '}.$fnmatch.q{', 'g') as y(img)
          )
        ) x
      )
    });
    print "# Deleted unreferenced images: $cnt\n";
}


sub findunused {
    my $imgs = $db->q('SELECT id FROM images')->kvv;
    printf "# Items in `images'... %d\n", scalar keys %$imgs;
    my($size, $count, $left) = (0,0,0);
    find {
        no_chdir => 1,
        wanted => sub {
            return if -d;
            if($File::Find::name !~ /($fnmatch)$/) {
                print "# Unknown file: $File::Find::name\n" if $File::Find::name =~ /$dirmatch/;
            } elsif(!$imgs->{$2.$3}) {
                $size += -s;
                $count++;
                printf "rm '%s' # %d KiB, https://s.vndb.org%s\n", $File::Find::name, (-s)/1024, $1;
            } else {
                $left++;
            }
        }
    }, "$ENV{VNDB_VAR}/static";
    printf "# Deleted %d files, left %d files, saved %d KiB\n", $count, $left, $size/1024;
}


cleandb;
findunused;
