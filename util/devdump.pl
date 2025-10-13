#!/usr/bin/env perl

# This script generates the devdump.tar.gz
# See https://vndb.org/d8#3 for info.

use v5.36;
use autodie;
use FU::Pg;

my $db = FU::Pg->connect('dbname=vndb user=vndb');

sub ids($l) { join ',', map "'$_'", @$l }
sub idq($q) { ids $db->q($q)->flat }

chdir($ENV{VNDB_VAR}//'var');


# Figure out which DB entries to export

my $large = ($ARGV[0]||'') eq 'large';

my $vids = $large ? 'SELECT id FROM vn' : ids [qw/v3 v17 v97 v183 v264 v266 v384 v407 v1910 v2932 v5922 v6438 v9837/];
my $staff = $large ? 'SELECT id FROM staff' : idq(
    "SELECT c2.itemid FROM vn_staff_hist  v JOIN changes c ON c.id = v.chid JOIN staff_alias_hist a ON a.aid = v.aid JOIN changes c2 ON c2.id = a.chid WHERE c.itemid IN($vids) "
   ."UNION "
   ."SELECT c2.itemid FROM vn_seiyuu_hist v JOIN changes c ON c.id = v.chid JOIN staff_alias_hist a ON a.aid = v.aid JOIN changes c2 ON c2.id = a.chid WHERE c.itemid IN($vids)"
);
my $releases = $large ? 'SELECT id FROM releases' : idq(
    "SELECT DISTINCT c.itemid FROM releases_vn_hist v JOIN changes c ON c.id = v.chid WHERE v.vid IN($vids)"
);
my $producers = $large ? 'SELECT id FROM producers' : idq(
    "SELECT pid FROM releases_producers_hist p JOIN changes c ON c.id = p.chid WHERE c.itemid IN($releases)"
);
my $characters = $large ? 'SELECT id FROM chars' : idq(
    "SELECT DISTINCT c.itemid FROM chars_vns_hist e JOIN changes c ON c.id = e.chid WHERE e.vid IN($vids) "
   ."UNION "
   ."SELECT DISTINCT h.main FROM chars_vns_hist e JOIN changes c ON c.id = e.chid JOIN chars_hist h ON h.chid = e.chid WHERE e.vid IN($vids) AND h.main IS NOT NULL"
);
my $imageids = !$large && $db->q("
         SELECT image FROM chars_hist           ch JOIN changes c ON c.id = ch.chid WHERE c.itemid IN($characters) AND ch.image IS NOT NULL
   UNION SELECT image FROM vn_hist              vh JOIN changes c ON c.id = vh.chid WHERE c.itemid IN($vids) AND vh.image IS NOT NULL
   UNION SELECT scr   FROM vn_screenshots_hist  vs JOIN changes c ON c.id = vs.chid WHERE c.itemid IN($vids)
   UNION SELECT img   FROM releases_images_hist ri JOIN changes c ON c.id = ri.chid WHERE c.itemid IN($releases)
")->flat;
my $images = $large ? 'SELECT id FROM images' : ids($imageids);


# Helper function to copy a table or SQL statement. Can do modifications on a
# few columns (the $specials).
sub copy($dest, $sql ||= "SELECT * FROM $dest", $specials ||= {}) {
    warn "$dest...\n";

    my @cols = grep !($specials->{$_} && $specials->{$_} eq 'del'), map $_->{name}, $db->q($sql)->columns->@*;

    printf "COPY %s (%s) FROM stdin;\n", $dest, join ', ', @cols;

    $sql = "SELECT " . join(',', map {
        my $s = $specials->{$_} || '';
        $s eq 'user' ? "CASE WHEN vndbid_num($_) % 10 = 0 THEN NULL ELSE vndbid('u', vndbid_num($_) % 10) END AS $_" : $_;
    } @cols) . " FROM ($sql) AS x";
    #warn $sql;
    my $c = $db->copy("COPY ($sql) TO STDOUT");
    my $v;
    print $v while ($v = $c->read);
    print "\\.\n\n";
}



# Helper function to copy a full DB entry with history and all (doesn't handle references)
sub copy_entry($tables, $ids) {
    copy changes => "SELECT * FROM changes WHERE itemid IN($ids)", {requester => 'user', ip => 'del'};
    for(@$tables) {
        my $add = '';
        $add = " AND vid IN($vids)" if /^releases_vn/ || /^vn_relations/ || /^chars_vns/;
        my %spec = ();
        $spec{prod} = 'del' if /^staff(?:_hist)?$/;
        copy $_          => "SELECT *   FROM $_ WHERE id IN($ids) $add", \%spec;
        copy "${_}_hist" => "SELECT x.* FROM ${_}_hist x JOIN changes c ON c.id = x.chid WHERE c.itemid IN($ids) $add", \%spec;
    }
}


{
    open my $OUT, '>:utf8', 'dump.sql';
    select $OUT;

    print "-- This file replaces 'sql/all.sql'.\n";
    print "\\set ON_ERROR_STOP 1\n";
    print "\\i sql/util.sql\n";
    print "\\i sql/schema.sql\n";
    print "\\i sql/data.sql\n";
    print "\\i sql/func.sql\n";
    print "\\i sql/editfunc.sql\n";

    # Copy over all sequence values
    my @seq = sort $db->q(
        "SELECT oid::regclass::text FROM pg_class WHERE relkind = 'S' AND relnamespace = 'public'::regnamespace"
    )->flat->@*;
    printf "SELECT setval('%s', %d);\n", $_, $db->q('SELECT nextval($1::text)', $_)->val for @seq;

    # A few pre-defined users
    # This password is 'hunter2' with the default salt
    my $pass = '000100000801ec4185fed438752d6b3b968e2b2cd045f70005cb7e10cafdbb694a82246bd34a065b6e977e0c3dcc';
    for(
        [ 'u2', 'admin', 'admin@vndb.org', 'true',  'true'],
        [ 'u3', 'mod',   'mod@vndb.org',   'false', 'true'],
        [ 'u4', 'user1', 'user1@vndb.org', 'false', 'false'],
        [ 'u5', 'user2', 'user2@vndb.org', 'false', 'false'],
        [ 'u6', 'user3', 'user3@vndb.org', 'false', 'false'],
        [ 'u7', 'user4', 'user4@vndb.org', 'false', 'false'],
        [ 'u8', 'user5', 'user5@vndb.org', 'false', 'false'],
        [ 'u9', 'user6', 'user6@vndb.org', 'false', 'false'],
    ) {
        printf "INSERT INTO users (id, username, email_confirmed, perm_dbmod, perm_tagmod) VALUES ('%s', '%s', true, '%s', '%s');\n", @{$_}[0,1,4,4];
        printf "INSERT INTO users_shadow (id, mail, perm_usermod, passwd) VALUES ('%s', '%s', %s, decode('%s', 'hex'));\n", @{$_}[0,2,3], $pass;
        printf "INSERT INTO users_prefs (id) VALUES ('%s');\n", $_->[0];
    }
    print "SELECT ulist_labels_create(id) FROM users;\n";

    # Tags & traits
    copy_entry [qw/tags tags_parents/], 'SELECT id FROM tags';
    copy_entry [qw/traits traits_parents/], 'SELECT id FROM traits';

    # Wikidata (TODO: This could be a lot more selective)
    copy 'wikidata';

    copy extlinks => "SELECT id, site, c_ref, value, data FROM extlinks WHERE id IN(
             SELECT link FROM releases_extlinks_hist  re JOIN changes c ON c.id = re.chid WHERE c.itemid IN($releases)
       UNION SELECT link FROM staff_extlinks_hist     se JOIN changes c ON c.id = se.chid WHERE c.itemid IN($staff)
       UNION SELECT link FROM producers_extlinks_hist pe JOIN changes c ON c.id = pe.chid WHERE c.itemid IN($producers)
       UNION SELECT link FROM vn_extlinks_hist        ve JOIN changes c ON c.id = ve.chid WHERE c.itemid IN($vids)
    )";

    # Image metadata
    copy images => "SELECT * FROM images WHERE id IN($images)", { uploader => 'user' };
    copy image_votes => "SELECT DISTINCT ON (id,vndbid('u', vndbid_num(uid)%10+10)) * FROM image_votes WHERE id IN($images)", { uid => 'user' };

    # Threads (announcements)
    my $threads = idq("SELECT tid FROM threads_boards b WHERE b.type = 'an'");
    copy threads        => "SELECT * FROM threads WHERE id IN($threads)";
    copy threads_boards => "SELECT * FROM threads_boards WHERE tid IN($threads)";
    copy threads_posts  => "SELECT * FROM threads_posts WHERE tid IN($threads)", { uid => 'user' };

    # Doc pages
    copy_entry ['docs'], 'SELECT id FROM docs';

    # Staff
    copy_entry [qw/staff staff_alias staff_extlinks/], $staff;

    # Producers (TODO: Relations)
    copy_entry [qw/producers producers_extlinks/], $producers;

    # Characters
    copy_entry [qw/chars chars_alias chars_names chars_traits chars_vns/], $characters;

    # Visual novels
    copy anime => "SELECT DISTINCT a.* FROM anime a JOIN vn_anime_hist v ON v.aid = a.id JOIN changes c ON c.id = v.chid WHERE c.itemid IN($vids)";
    copy_entry [qw/vn vn_anime vn_editions vn_extlinks vn_seiyuu vn_staff vn_relations vn_screenshots vn_titles/], $vids;

    # VN-related niceties
    copy vn_length_votes => "SELECT DISTINCT ON (vid,vndbid_num(uid)%10) * FROM vn_length_votes WHERE NOT private AND vid IN($vids)", {uid => 'user'};
    copy tags_vn     => "SELECT DISTINCT ON (tag,vid,vndbid_num(uid)%10) * FROM tags_vn WHERE vid IN($vids)", {uid => 'user'};
    copy quotes      => "SELECT * FROM quotes WHERE rand IS NOT NULL AND vid IN($vids)", {addedby => 'user'};
    copy ulist_vns   => "SELECT vid, vndbid('u', vndbid_num(uid)%8+2) AS uid, MIN(vote_date) AS vote_date, '{7}' AS labels, false AS c_private
                              , (percentile_cont((vndbid_num(uid)%8+1)::float/9) WITHIN GROUP (ORDER BY vote))::smallint AS vote
                           FROM ulist_vns WHERE vid IN($vids) AND vote IS NOT NULL GROUP BY vid, vndbid_num(uid)%8", {uid => 'user'};

    # Releases
    copy 'drm';
    copy 'engines';
    copy_entry [qw/releases releases_drm releases_extlinks releases_images releases_media releases_platforms releases_producers releases_supersedes releases_titles releases_vn/], $releases;

    print "\\i sql/tableattrs.sql\n";
    print "\\i sql/triggers.sql\n";

    # Update some caches
    print "SELECT tag_vn_calc(NULL);\n";
    print "SELECT traits_chars_calc(NULL);\n";
    print "SELECT update_vncache(NULL);\n";
    print "SELECT update_stats_cache_full();\n";
    print "SELECT update_vnvotestats();\n";
    print "SELECT update_users_ulist_stats(NULL);\n";
    print "SELECT update_images_cache(NULL);\n";
    print "SELECT count(*) FROM (SELECT update_search(id) FROM $_) x;\n" for (qw/chars producers vn releases staff tags traits/);
    print "UPDATE users u SET c_tags = (SELECT COUNT(*) FROM tags_vn v WHERE v.uid = u.id);\n";
    print "UPDATE users u SET c_changes = (SELECT COUNT(*) FROM changes c WHERE c.requester = u.id);\n";

    print "\\set ON_ERROR_STOP 0\n";
    print "\\i sql/perms.sql\n";
    print "VACUUM ANALYZE;\n";

    select STDOUT;
    close $OUT;
}



# Now figure out which images we need, and throw everything in a tarball
if(!$large) {
    sub img($dir,$id) { sprintf 'static/%s/%02d/%d.jpg', $dir, $id%100, $id }
    my @imgpaths = sort map {
        my($t,$id) = /([a-z]+)([0-9]+)/;
        (
            img($t, $id),
            $t eq 'sf' ? img('sf.t', $id) : (),
            $t eq 'cv' && -f img('cv.t', $id) ? img('cv.t', $id) : (),
        )
    } @$imageids;

    system("tar -czf devdump.tar.gz dump.sql ".join ' ', @imgpaths);
    unlink 'dump.sql';
}
