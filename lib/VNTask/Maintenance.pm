package VNTask::Maintenance;

use v5.36;
use VNTask::Core;
use POSIX 'strftime';
use Time::HiRes 'time';
use File::Find 'find';


task logrotate => delay => '23h', align_div => '24h', align_add => '1m', sub {
    my $today = strftime '%Y%m%d', gmtime;
    my $oldest = strftime '%Y%m%d', gmtime(time - 30*24*3600);

    my $dir = config->{var_path}.'/log';
    opendir my $D, $dir or die "Unable to read $dir: $!";
    while (local $_ = readdir $D) {
        next if /^\./ || /~$/ || !-f "$dir/$_";
        if (/-([0-9]{8})$/) {
            unlink "$dir/$_" or warn "Unable to rm $dir/$_: $!" if $1 lt $oldest;
        } elsif (!-f "$dir/$_-$today") {
            rename "$dir/$_", "$dir/$_-$today" or warn "Unable to move $dir/$_: $!";
        }
    }
};


task httpcache => delay => '40m', align_div => '1h', align_add => '10m', sub($task) {
    my $dir = config->{var_path}.'/tmp/task-http';
    opendir my $D, $dir or return;
    my($count, $size) = (0,0);
    while (local $_ = readdir $D) {
        $_ = "$dir/$_";
        next if !-f || (stat)[10] > time-60;
        $count++;
        $size += -s;
        unlink or warn "Unable to rm $_: $!";
    }
    $task->done('%d files %.0f KiB', $count, $size/1024);
};


# VN cache uses current date to determine which releases have been "released", so should be updated daily.
# (Can be limited to only update VNs with releases around the current date, but this is fast enough)
task vncache => delay => '23h', align_div => '24h', align_add => '10m', sub($task) {
    $task->exec('SELECT update_vncache(NULL)');
};


my @daily = (
    # Delete tags assigned to Multi that also have (possibly inherited) votes from other users.
    cleanmultitags => q{
        WITH RECURSIVE
          t_votes(tag,vid,uid) AS (SELECT tv.tag, tv.vid, tv.uid FROM tags_vn tv LEFT JOIN users u ON u.id = tv.uid WHERE tv.uid IS DISTINCT FROM 'u1' AND (u.id IS NULL OR u.perm_tag)),
          t_inherit(tag,vid,uid) AS (SELECT * FROM t_votes UNION SELECT tp.parent, th.vid, th.uid FROM t_inherit th JOIN tags_parents tp ON tp.id = th.tag),
          t_nonmulti(tag,vid) AS (SELECT DISTINCT tag, vid FROM t_inherit),
          t_del(tag,vid) AS (SELECT tv.tag, tv.vid FROM tags_vn tv JOIN t_nonmulti tn ON (tn.tag,tn.vid) = (tv.tag,tv.vid) WHERE tv.uid = 'u1')
        DELETE FROM tags_vn tv WHERE tv.uid = 'u1' AND EXISTS(SELECT 1 FROM t_del td WHERE (td.tag,td.vid) = (tv.tag,tv.vid))
    },

    vnvotestats => 'SELECT update_vnvotestats()',

    # These caches are only partially updated through triggers. Some actions (e.g.
    # tag/trait tree changes, user permission changes, etc) do not trigger a cache
    # refresh, so these must be run periodically.
    tagcache => 'SELECT tag_vn_calc(NULL)',
    traitcache => 'SELECT traits_chars_calc(NULL)',
    lengthcache => 'SELECT update_vn_length_cache(NULL)',
    imagecache => 'SELECT update_images_cache(NULL)',
    reviewcache => 'SELECT update_reviews_votes_cache(NULL)',
    quotescache => 'SELECT quotes_rand_calc()',

    deleteusers => 'SELECT user_delete(id, null) FROM users_shadow WHERE delete_at < NOW()',
    deleteunconfirmed => "DELETE FROM users WHERE registered < NOW()-'1 week'::interval AND NOT email_confirmed",
    cleansessions => "DELETE FROM sessions WHERE expires < NOW() AND type <> 'api2'",

    cleannotifications => q{
        DELETE FROM notifications WHERE read < NOW()-'1 month'::interval;
        DELETE FROM notifications WHERE id IN (
            SELECT id FROM (SELECT id, row_number() OVER (PARTITION BY uid ORDER BY id DESC) > 500 from notifications) AS x(id,del) WHERE x.del
        );
    },

    cleanthrottle => q{
        DELETE FROM login_throttle WHERE timeout < NOW();
        DELETE FROM reset_throttle WHERE timeout < NOW();
        DELETE FROM registration_throttle WHERE timeout < NOW();
    },

    # Shouldn't be necessary, but it's fast anyway
    statcache => 'SELECT update_stats_cache_full()',
);

task dailysql => delay => '20h', align_div => '24h', align_add => '06:30:00', sub($task) {
    my $match = $task->arg || '.';
    for my($n, $sql) (@daily) {
        next if $n !~ $match;
        $task->item($n);
        my $s = time;
        my $res = $task->exec($sql);
        warn sprintf "%d rows in %.0fms\n", $res, (time-$s)*1000;
    }
    $task->item('');
};





task cleanimages => delay => '6d', align_div => '7d', align_add => '1d 06:10:00', sub($task) {
    my $dirmatch = '/(cv|ch|sf|st)(?:\.orig|\.t)?/';
    my $fnmatch = $dirmatch.'[0-9][0-9]/([1-9][0-9]{0,6})\.(?:jpg|webp|png|avif|jxl)?';

    # Delete all images from the `images` table that are not referenced from
    # *anywhere* in the database, including old revisions and links found in
    # comments, descriptions and docs.
    # The 30 (100, in the case of screenshots) most recently uploaded images of
    # each type are also kept because there's a good chance they will get
    # referenced from somewhere, soon.
    my $rmrows = $task->sql(q{
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
    })->exec;

    my $imgs = $task->sql('SELECT id FROM images')->kvv;
    my($size, $rmsize, $files, $rmfiles) = (0,0,0,0);
    find {
        no_chdir => 1,
        wanted => sub {
            return if -d;
            if($File::Find::name !~ /$fnmatch$/) {
                warn "Unknown file: $File::Find::name\n" if $File::Find::name =~ /$dirmatch/;
            } elsif(!$imgs->{$1.$2}) {
                $rmsize += -s;
                $rmfiles++;
                unlink $File::Find::name;
            } else {
                $size += -s;
                $files++;
            }
        }
    }, config->{var_path}."/static";

    warn sprintf "Deleted %d/%d rows and %d/%d files (%.0f/%.0f KiB)\n",
        $rmrows, scalar keys %$imgs,
        $rmfiles, $files,
        $rmsize/1024, $size/1024;
};

1;
