#!/usr/bin/env perl
my $HELP=<<_;
Usage:

util/dbdump.pl export-db output.tar.zst

  Write a full database export as a .tar.zst

util/dbdump.pl export-img output-dir

  Create or update a directory with hardlinks to images.

util/dbdump.pl export-data data.sql

  Create an SQL script that is usable as replacement for 'sql/all.sql'.
  (Similar to the dump created by devdump.pl, except this one includes *all* data)

  This allows recreating the full database using the definitions in sql/*.
  The script does not rely on column order, so can be used to re-order table columns.

util/dbdump.pl export-votes output.gz
util/dbdump.pl export-tags output.gz
util/dbdump.pl export-traits output.gz
_

# TODO:
# - Import
# - Consolidate with devdump.pl?

use v5.36;
use autodie;
use FU::Pg;
use FU::Util 'json_format';
use File::Copy 'cp';
use File::Find 'find';
use File::Path 'rmtree';
use Time::HiRes 'time';

use lib 'lib';
use VNDB::Schema;
use VNDB::ExtLinks;

$ENV{VNDB_VAR} //= 'var';

# Ridiculous query to export 'ulist_vns' with private labels removed.
# Since doing a lookup in ulist_labels for each row+label in ulist_vns is
# rather slow, this query takes a shortcut: for users that do not have any
# private labels at all (i.e. the common case), this query just dumps the rows
# without any modification. Only for users that have at least one private label
# are the labels filtered.
my $sql_ulist_vns_cols = q{
    uid, vid, added::date, lastmod::date, vote_date::date, started, finished, vote, notes
};
my $sql_ulist_vns = qq{
  SELECT * FROM (
    SELECT $sql_ulist_vns_cols, array_agg(lblid ORDER BY lblid) AS labels
      FROM ulist_vns, unnest(labels) x(lblid)
     WHERE NOT c_private
       AND NOT EXISTS(SELECT 1 FROM ulist_labels WHERE uid = ulist_vns.uid AND id = lblid AND private)
       AND uid IN(SELECT uid FROM ulist_labels WHERE private)
     GROUP BY uid, vid
    UNION ALL
    SELECT $sql_ulist_vns_cols, labels
      FROM ulist_vns
     WHERE NOT c_private
       AND uid NOT IN(SELECT uid FROM ulist_labels WHERE private)
  ) z
  WHERE vid IN(SELECT id FROM vn WHERE NOT hidden)
  ORDER BY uid, vid
};



# Tables and columns to export.
#
# Tables are exported with an explicit ORDER BY to make them more deterministic
# and avoid potentially leaking information about internal state (such as when
# a user last updated their account).
#
# Hidden DB entries, private user lists and various other rows with no
# interesting references are excluded from the dumps. Keeping all references
# consistent with those omissions complicates the WHERE clauses somewhat.
my %tables = (
    anime               => { where => 'x.id IN(SELECT va.aid FROM vn_anime va JOIN vn v ON v.id = va.id WHERE NOT v.hidden)' },
    chars               => { where => 'NOT x.hidden' },
    chars_alias         => { where => 'x.id IN(SELECT id FROM chars WHERE NOT hidden)' },
    chars_names         => { where => 'x.id IN(SELECT id FROM chars WHERE NOT hidden)' },
    chars_traits        => { where => 'x.id IN(SELECT id FROM chars WHERE NOT hidden) AND tid IN(SELECT id FROM traits WHERE NOT hidden)' },
    chars_vns           => { where => 'x.id IN(SELECT id FROM chars WHERE NOT hidden)'
                                .' AND x.vid IN(SELECT id FROM vn WHERE NOT hidden)'
                                .' AND (x.rid IS NULL OR x.rid IN(SELECT id FROM releases WHERE NOT hidden))'
                           , order => 'x.id, x.vid, x.rid' },
    docs                => { where => 'NOT x.hidden' },
    drm                 => { where => 'c_ref > 0' },
    engines             => { where => 'c_ref > 0' },
    entry_meta          => { sql => "SELECT itemid, min(added)::date AS created, max(added)::date AS lastmod, max(rev) AS revision
                                          , count(*) filter (where requester <> 'u1') AS num_edits
                                          , count(distinct requester) filter (where requester <> 'u1') AS num_users
                                       FROM (SELECT itemid, added, rev, requester, first_value(ihid) OVER (PARTITION BY itemid ORDER BY rev DESC) AS hidden FROM changes) x
                                      WHERE NOT hidden GROUP BY itemid ORDER BY itemid" },
    extlinks            => { where => 'x.c_ref' },
    images              => { where => "x.c_weight > 0" }, # Only images with a positive weight are referenced.
    image_votes         => { where => "x.id IN(SELECT id FROM images WHERE c_weight > 0)", order => 'x.uid, x.id' },
    producers           => { where => 'NOT x.hidden' },
    producers_extlinks  => { where => 'x.id IN(SELECT id FROM producers WHERE NOT hidden)' },
    producers_relations => { where => 'x.id IN(SELECT id FROM producers WHERE NOT hidden)' },
    quotes              => { where => 'NOT hidden AND x.vid IN(SELECT id FROM vn WHERE NOT hidden)' },
    releases            => { where => 'NOT x.hidden' },
    releases_drm        => { where => 'x.id IN(SELECT id FROM releases WHERE NOT hidden)' },
    releases_extlinks   => { where => 'x.id IN(SELECT id FROM releases WHERE NOT hidden)' },
    releases_images     => { where => 'x.id IN(SELECT id FROM releases WHERE NOT hidden)' },
    releases_media      => { where => 'x.id IN(SELECT id FROM releases WHERE NOT hidden)' },
    releases_platforms  => { where => 'x.id IN(SELECT id FROM releases WHERE NOT hidden)' },
    releases_producers  => { where => 'x.id IN(SELECT id FROM releases WHERE NOT hidden) AND pid IN(SELECT id FROM producers WHERE NOT hidden)' },
    releases_supersedes => { where => 'x.id IN(SELECT id FROM releases WHERE NOT hidden) AND rid IN(SELECT id FROM releases WHERE NOT hidden)' },
    releases_titles     => { where => 'x.id IN(SELECT id FROM releases WHERE NOT hidden)' },
    releases_vn         => { where => 'x.id IN(SELECT id FROM releases WHERE NOT hidden) AND vid IN(SELECT id FROM vn WHERE NOT hidden)' },
    rlists              => { where => 'EXISTS(SELECT 1 FROM releases r'
                                                    .' JOIN releases_vn rv ON rv.id = r.id'
                                                    .' JOIN vn v ON v.id = rv.vid'
                                                    .' JOIN ulist_vns uv ON uv.vid = rv.vid'
                                                   .' WHERE r.id = x.rid AND uv.uid = x.uid AND NOT r.hidden AND NOT v.hidden AND NOT uv.c_private)' },
    staff               => { where => 'NOT x.hidden' },
    staff_alias         => { where => 'x.id IN(SELECT id FROM staff WHERE NOT hidden)' },
    staff_extlinks      => { where => 'x.id IN(SELECT id FROM staff WHERE NOT hidden)' },
    tags                => { where => 'NOT x.hidden' },
    tags_parents        => { where => 'x.id IN(SELECT id FROM tags WHERE NOT hidden)' },
    tags_vn             => { where => 'x.tag IN(SELECT id FROM tags WHERE NOT hidden) AND x.vid IN(SELECT id FROM vn WHERE NOT hidden)', order => 'x.tag, x.vid, x.uid, x.date' },
    traits              => { where => 'NOT x.hidden' },
    traits_parents      => { where => 'x.id IN(SELECT id FROM traits WHERE NOT hidden)' },
    ulist_labels        => { where => 'NOT x.private AND EXISTS(SELECT 1 FROM ulist_vns uv JOIN vn v ON v.id = uv.vid
                                        WHERE NOT v.hidden AND uv.labels && ARRAY[x.id] AND x.uid = uv.uid)' },
    ulist_vns           => { sql => $sql_ulist_vns },
    users               => { where => 'x.username IS NOT NULL AND ('
                                 .'    x.id IN(SELECT DISTINCT uid FROM ulist_vns WHERE NOT c_private)'
                                 .' OR x.id IN(SELECT DISTINCT uid FROM tags_vn)'
                                 .' OR x.id IN(SELECT DISTINCT uid FROM image_votes)'
                                 .' OR x.id IN(SELECT DISTINCT uid FROM vn_length_votes WHERE NOT private)'
                                 .' OR x.id IN(SELECT DISTINCT uid FROM vn_image_votes))' },
    vn                  => { where => 'NOT x.hidden' },
    vn_anime            => { where => 'x.id IN(SELECT id FROM vn WHERE NOT hidden)' },
    vn_editions         => { where => 'x.id IN(SELECT id FROM vn WHERE NOT hidden)' },
    vn_extlinks         => { where => 'x.id IN(SELECT id FROM vn WHERE NOT hidden)' },
    vn_relations        => { where => 'x.id IN(SELECT id FROM vn WHERE NOT hidden)' },
    vn_screenshots      => { where => 'x.id IN(SELECT id FROM vn WHERE NOT hidden)' },
    vn_seiyuu           => { where => 'x.id IN(SELECT id FROM vn WHERE NOT hidden)'
                                .' AND x.aid IN(SELECT sa.aid FROM staff_alias sa JOIN staff s ON s.id = sa.id WHERE NOT s.hidden)'
                                .' AND x.cid IN(SELECT id FROM chars WHERE NOT hidden)' },
    vn_staff            => { where => 'x.id IN(SELECT id FROM vn WHERE NOT hidden) AND x.aid IN(SELECT sa.aid FROM staff_alias sa JOIN staff s ON s.id = sa.id WHERE NOT s.hidden)'
                           , order => 'x.id, x.eid, x.aid, x.role' },
    vn_titles           => { where => 'x.id IN(SELECT id FROM vn WHERE NOT hidden)' },
    vn_image_votes      => { where => 'x.vid IN(SELECT id FROM vn WHERE NOT hidden)'
                                .' AND x.img IN(SELECT id FROM images WHERE c_weight > 0)' },
    vn_length_votes     => { where => 'x.vid IN(SELECT id FROM vn WHERE NOT hidden) AND NOT x.private'
                           , order => 'x.vid, x.uid' },
    wikidata            => { where => q{x.id IN(SELECT value::int FROM extlinks WHERE site = 'wikidata' AND c_ref)} },
);

my @tables = map +{ name => $_, %{$tables{$_}} }, sort keys %tables;
my $schema = VNDB::Schema::schema;
my $types = VNDB::Schema::types;
my $references = VNDB::Schema::references;

my $db = FU::Pg->connect('dbname=vndb user=vndb');
$db->exec('SET TIME ZONE +0');


sub consistent_snapshot($func) {
    my $standby = $db->q('SELECT pg_is_in_recovery()')->val;
    $db->exec($standby ? 'SELECT pg_wal_replay_pause()' : 'BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE');
    eval { $func->() };
    warn $@ if length $@;
    $db->exec('SELECT pg_wal_replay_resume()') if $standby;
}


sub table_order($tbl) {
    my $s = $schema->{$tbl};
    my $c = $tables{$tbl};
    my $o = $s->{primary} ? join ', ', map "x.$_", $s->{primary}->@* : $c ? $c->{order} : '';
    $o ? "ORDER BY $o" : '';
}


sub export_timestamp($dest) {
    open my $F, '>', $dest;
    printf $F "%s\n", $db->q('SELECT date_trunc(\'second\', NOW())')->text->val;
}


sub export_table($dest, $table) {
    my $schema = $schema->{$table->{name}};
    my @cols = grep $_->{pub}, @{$schema->{cols}};
    die "No columns to export for table '$table->{name}'\n" if !@cols;;

    my $fn = "$dest/$table->{name}";

    my $sql = $table->{sql} // do {
        my %isuid =
            map +($_->{from_cols}[0], 1),
            grep $_->{to_table} eq 'users' && $_->{to_cols}[0] eq 'id' && $_->{from_table} eq $table->{name}, @$references;
        my $join = '';

        my $cols = join ', ', map {
            # For uid columns, check against the users table and export NULL for deleted accounts
            $isuid{$_->{name}} ? do {
                my $t = "u_$_->{name}";
                $join .= " LEFT JOIN users $t ON $t.id = x.$_->{name}";
                "CASE WHEN $t.username IS NULL THEN NULL ELSE $t.id END"
            }
            # Truncate all timestamptz columns to a day, to avoid leaking privacy-sensitive info.
            : $_->{type} eq 'timestamptz' ? "x.$_->{name}::date"
            : qq{x.$_->{name}}
        } @cols;

        my $where = $table->{where} ? "WHERE $table->{where}" : '';
        my $order = table_order $table->{name};
        die "Table '$table->{name}' is missing an ORDER BY clause\n" if !$order;
        qq{SELECT $cols FROM $table->{name} x $join $where $order}
    };

    my $start = time;
    my $cp = $db->copy(qq{COPY ($sql) TO STDOUT});
    open my $F, '>:utf8', $fn;
    my $v;
    print $F $v while($v = $cp->read);
    close $F;

    #printf "# Dumped %s in %.3fs\n", $table->{name}, time-$start;

    open $F, '>', "$fn.header";
    print $F join "\t", map $_->{name}, @cols;
    print $F "\n";
    close $F;
}


sub export_schema($plain, $dest) {
    open my $F, '>', $dest;
    for my $table (@tables) {
        my $schema = $schema->{$table->{name}};
        my @primary = grep { my $n=$_; !!grep $_->{name} eq $n && $_->{pub}, $schema->{cols}->@* } ($schema->{primary}||[])->@*;
        print $F "\n";
        print $F "CREATE TABLE $table->{name} (\n";
        print $F join ",\n", map
            "  $_->{decl}"
                =~ s/ serial/ integer/ir
                =~ s/ +(?:check|constraint|default) +.*//ir
                =~ s/ timestamptz/ date/ir
                =~ s/(vndbid(?:\([^\)]+\))?)/$plain ? 'text' : $1/er,
            grep $_->{pub}, @{$schema->{cols}};
        print $F ",\n  PRIMARY KEY(".join(', ', map "$_", @primary).")" if @primary;
        print $F "\n);\n";
    }
}


sub export_import_script($dest) {
    open my $F, '>', $dest;
    print $F <<~'_';
    -- This script will create the necessary tables and import all data into an
    -- existing PostgreSQL database.
    --
    -- Usage:
    --   Run a 'CREATE DATABASE $database' somewhere.
    --   psql -U $user $database -f import.sql
    --
    -- The imported database does not include any indices, other than primary keys.
    -- You may want to create some indices by hand to speed up complex queries.
    --
    -- This script automatically detects whether you have the 'vndbid' type loaded
    -- into the database and will use that when it is available. To use it, load
    -- sql/vndbid.sql from the VNDB source repository into your database before
    -- running this import script. If the type is not detected, vndbid's will be
    -- imported into a generic text column instead. This works fine for most use
    -- cases, but is slightly less efficient, lacks some convenience functions and
    -- identifiers will compare and sort differently.
    --
    -- Uncomment to import the schema and data into a separate namespace:
    --CREATE SCHEMA vndb;
    --SET search_path TO vndb;
    _

    print $F "\n\n";
    my %types = map +($_->{type}, 1), grep $_->{pub}, map @{$schema->{$_->{name}}{cols}}, @tables;
    print $F "$types->{$_}{decl}\n" for (sort grep $types->{$_}, keys %types);

    print $F "\n\n";
    print $F <<~'_';
    SELECT EXISTS(SELECT 1 FROM pg_type WHERE typname = 'vndbtag') as has_vndbtag\gset
    \if :has_vndbtag
      \i schema_vndbid.sql
    \else
      \i schema_plain.sql
    \endif
    _

    print $F "\n\n";
    print $F "-- You can comment out tables you don't need, to speed up the import and save some disk space.\n";
    print $F "\\copy $_->{name} from 'db/$_->{name}'\n" for @tables;

    print $F "\n\n";
    print $F "-- These are included to verify the internal consistency of the dump, you can safely comment out this part.\n";
    for my $ref (@$references) {
        next if !$tables{$ref->{from_table}} || !$tables{$ref->{to_table}};
        my %pub = map +($_->{name}, 1), grep $_->{pub}, @{$schema->{$ref->{from_table}}{cols}};
        next if grep !$pub{$_}, @{$ref->{from_cols}};
        print $F "$ref->{decl}\n";
    }

    print $F "\n\n";
    print $F "-- Sparse documentation, but it's something!\n";
    my $L = \%VNDB::ExtLinks::LINKS;
    for my $table (@tables) {
        my $schema = $schema->{$table->{name}};
        print $F "COMMENT ON TABLE $table->{name} IS ".$db->escape_literal($schema->{comment}).";\n" if $schema->{comment};
        my $l = ($schema->{dbentry_type} && $L->{$schema->{dbentry_type}}) || {};
        for (grep $_->{pub}, $schema->{cols}->@*) {
            $_->{comment} = "$l->{$_->{name}}{label}, $l->{$_->{name}}{fmt} $_->{comment}" if $l->{$_->{name}} && $l->{$_->{name}}{fmt};
            print $F "COMMENT ON COLUMN $table->{name}.$_->{name} IS ".$db->escape_literal($_->{comment}).";\n" if $_->{comment};
        }
    }
}


sub export_db($dest) {
    my @static = qw{
        LICENSE-CC0.txt
        LICENSE-CC-BY-NC-SA.txt
        LICENSE-DBCL.txt
        LICENSE-ODBL.txt
        README.txt
    };

    rmtree "${dest}_dir";
    mkdir "${dest}_dir";
    mkdir "${dest}_dir/db";

    cp "util/dump/$_", "${dest}_dir/$_" for @static;

    export_timestamp "${dest}_dir/TIMESTAMP";
    export_table "${dest}_dir/db", $_ for @tables;
    export_schema 0, "${dest}_dir/schema_vndbid.sql";
    export_schema 1, "${dest}_dir/schema_plain.sql";
    export_import_script "${dest}_dir/import.sql";

    #print "# Compressing\n";
    `tar -cf "$dest" -I 'zstd -7' --sort=name -C "${dest}_dir" @static import.sql schema_plain.sql schema_vndbid.sql TIMESTAMP db`;
    rmtree "${dest}_dir";
}


# Copy file while retaining access/modification times
sub cp_p($from, $to) {
    cp $from, $to;
    utime @{ [stat($from)] }[8,9], $to;
}


# XXX: This does not include images that are linked from descriptions; May want to borrow from util/unusedimages.pl to find those.
sub export_img($dest) {
    my(%scr, %cv);
    my %dir = (ch => {}, cv => \%cv, 'cv.t' => \%cv, sf => \%scr, 'sf.t' => \%scr);

    no autodie;
    mkdir ${dest};
    mkdir sprintf '%s/%s', $dest, $_ for keys %dir;
    mkdir sprintf '%s/%s/%02d', $dest, $_->[0], $_->[1] for map { my $d=$_; map [$d,$_], 0..99 } keys %dir;

    cp_p "util/dump/LICENSE-ODBL.txt", "$dest/LICENSE-ODBL.txt";
    cp_p "util/dump/README-img.txt", "$dest/README.txt";
    export_timestamp "$dest/TIMESTAMP";

    $dir{sf}{$_} = 1 for $db->q("SELECT vndbid_num(scr) FROM vn_screenshots x WHERE $tables{vn_screenshots}{where}")->flat->@*;
    $dir{cv}{$_} = 1 for $db->q("SELECT vndbid_num(image) FROM vn x WHERE image IS NOT NULL AND $tables{vn}{where}")->flat->@*;
    $dir{cv}{$_} = 1 for $db->q("SELECT vndbid_num(img) FROM releases_images x WHERE $tables{releases_images}{where}")->flat->@*;
    $dir{ch}{$_} = 1 for $db->q("SELECT vndbid_num(image) FROM chars x WHERE image IS NOT NULL AND $tables{chars}{where}")->flat->@*;
    undef $db;

    find {
        no_chdir => 1,
        wanted => sub {
            unlink $File::Find::name or warn "Unable to unlink $File::Find::name: $!\n"
                if $File::Find::name =~ m{(cv|cv\.t|ch|sf|sf\.t)/[0-9][0-9]/([0-9]+)\.jpg$} && !$dir{$1}{$2};
        }
    }, $dest;

    for my $d (keys %dir) {
        for my $i (keys %{$dir{$d}}) {
            my $f = sprintf('%s/%02d/%d.jpg', $d, $i % 100, $i);
            next if -e "$dest/$f";
            my $r = link "$ENV{VNDB_VAR}/static/$f", "$dest/$f";
            # Not all 'cv' images have a corresponding file in cv.t
            warn "Unable to link $f: $!\n" if !$r && $d ne 'cv.t';
        }
    }
}


sub export_data($dest) {
    my $F = *STDOUT;
    open $F, '>', $dest if $dest ne '-';
    binmode($F, ":utf8");
    select $F;
    print "\\set ON_ERROR_STOP 1\n";
    print "\\i sql/util.sql\n";
    print "\\i sql/schema.sql\n";
    # Would be nice if VNDB::Schema could list sequences, too.
    my @seq = sort $db->q(
        "SELECT oid::regclass::text FROM pg_class WHERE relkind = 'S' AND relnamespace = 'public'::regnamespace"
    )->flat->@*;
    printf "SELECT setval('%s', %d);\n", $_, $db->q('SELECT last_value FROM'.$db->escape_identifier($_))->val for @seq;
    for my $t (sort { $a->{name} cmp $b->{name} } values %$schema) {
        my $cols = join ',', map $_->{name}, grep $_->{decl} !~ /\sGENERATED\s/, $t->{cols}->@*;
        my $order = table_order $t->{name};
        print "\nCOPY $t->{name} ($cols) FROM STDIN;\n";
        my $cp = $db->copy("COPY (SELECT $cols FROM $t->{name} x $order) TO STDOUT");
        my $v;
        print $v while($v = $cp->read);
        print "\\.\n";
    }
    print "\\i sql/func.sql\n";
    print "\\i sql/editfunc.sql\n";
    print "\\i sql/tableattrs.sql\n";
    print "\\i sql/triggers.sql\n";
    print "\\set ON_ERROR_STOP 0\n";
    print "\\i sql/perms.sql\n";
}


sub export_votes($dest) {
    open my $F, '|-', "gzip >$dest";
    my $cp = $db->copy(q{COPY (
        SELECT vndbid_num(uv.vid)||' '||vndbid_num(uv.uid)||' '||uv.vote||' '||to_char(uv.vote_date, 'YYYY-MM-DD')
          FROM ulist_vns uv
          JOIN users u ON u.id = uv.uid
          JOIN vn v ON v.id = uv.vid
         WHERE NOT v.hidden
           AND NOT u.ign_votes
           AND uv.vote IS NOT NULL
           AND NOT uv.c_private
         ORDER BY uv.vid, uv.uid
       ) TO STDOUT
    });
    my $v;
    print $F $v while($v = $cp->read);
}


sub export_tags($dest) {
    my $lst = $db->q(q{
        SELECT vndbid_num(id) AS id, name, description, c_items AS vns, cat
             , string_to_array(alias, E'\n') AS aliases
             , NOT searchable AS meta, searchable, applicable
             , ARRAY(SELECT vndbid_num(parent) FROM tags_parents tp WHERE tp.id = t.id ORDER BY main DESC, parent) AS parents
        FROM tags t WHERE NOT hidden ORDER BY id
    })->allh;
    open my $F, '|-', "gzip >$dest";
    print $F json_format($lst, canonical => 1, utf8 => 1);
}


sub export_traits($dest) {
    my $lst = $db->q(q{
        SELECT vndbid_num(id) AS id, name, description, c_items AS chars
             , string_to_array(alias, E'\n') AS aliases
             , NOT searchable AS meta, searchable, applicable, sexual
             , ARRAY(SELECT vndbid_num(parent) FROM traits_parents tp WHERE tp.id = t.id ORDER BY main desc, parent) AS parents
        FROM traits t WHERE NOT hidden ORDER BY id
    })->allh;
    open my $F, '|-', "gzip >$dest";
    print $F json_format($lst, canonical => 1, utf8 => 1);
}


if($ARGV[0] && $ARGV[0] eq 'export-db' && $ARGV[1]) {
    consistent_snapshot sub { export_db $ARGV[1] };
} elsif($ARGV[0] && $ARGV[0] eq 'export-img' && $ARGV[1]) {
    export_img $ARGV[1];
} elsif($ARGV[0] && $ARGV[0] eq 'export-data' && $ARGV[1]) {
    export_data $ARGV[1];
} elsif($ARGV[0] && $ARGV[0] eq 'export-votes' && $ARGV[1]) {
    export_votes $ARGV[1];
} elsif($ARGV[0] && $ARGV[0] eq 'export-tags' && $ARGV[1]) {
    export_tags $ARGV[1];
} elsif($ARGV[0] && $ARGV[0] eq 'export-traits' && $ARGV[1]) {
    export_traits $ARGV[1];
} else {
    print $HELP;
}
