#!/usr/bin/perl
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

use strict;
use warnings;
use autodie;
use DBI;
use DBD::Pg;
use File::Copy 'cp';
use File::Find 'find';
use File::Path 'rmtree';
use Time::HiRes 'time';

use Cwd 'abs_path';
our $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/dbdump\.pl$}{}; }

use lib "$ROOT/lib";
use VNDB::Schema;


# Ridiculous query to export 'ulist_vns' with private labels removed.
# Since doing a lookup in ulist_labels for each row+label in ulist_vns is
# rather slow, this query takes a shortcut: for users that do not have any
# private labels at all (i.e. the common case), this query just dumps the rows
# without any modification. Only for users that have at least one private label
# are the labels filtered.
my $sql_ulist_vns_cols = q{
    uid, vid, date_trunc('day',added) AS added, date_trunc('day',lastmod) AS lastmod
  , date_trunc('day',vote_date), started, finished, vote, notes
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
    anime               => { where => 'id IN(SELECT va.aid FROM vn_anime va JOIN vn v ON v.id = va.id WHERE NOT v.hidden)' },
    chars               => { where => 'NOT hidden' },
    chars_traits        => { where => 'id IN(SELECT id FROM chars WHERE NOT hidden) AND tid IN(SELECT id FROM traits WHERE NOT hidden)' },
    chars_vns           => { where => 'id IN(SELECT id FROM chars WHERE NOT hidden)'
                                .' AND vid IN(SELECT id FROM vn WHERE NOT hidden)'
                                .' AND (rid IS NULL OR rid IN(SELECT id FROM releases WHERE NOT hidden))'
                           , order => 'id, vid, rid' },
    docs                => { where => 'NOT hidden' },
    images              => { where => "c_weight > 0" }, # Only images with a positive weight are referenced.
    image_votes         => { where => "id IN(SELECT id FROM images WHERE c_weight > 0)", order => 'uid, id' },
    producers           => { where => 'NOT hidden' },
    producers_relations => { where => 'id IN(SELECT id FROM producers WHERE NOT hidden)' },
    quotes              => { where => 'vid IN(SELECT id FROM vn WHERE NOT hidden)' },
    releases            => { where => 'NOT hidden' },
    releases_media      => { where => 'id IN(SELECT id FROM releases WHERE NOT hidden)' },
    releases_platforms  => { where => 'id IN(SELECT id FROM releases WHERE NOT hidden)' },
    releases_producers  => { where => 'id IN(SELECT id FROM releases WHERE NOT hidden) AND pid IN(SELECT id FROM producers WHERE NOT hidden)' },
    releases_titles     => { where => 'id IN(SELECT id FROM releases WHERE NOT hidden)' },
    releases_vn         => { where => 'id IN(SELECT id FROM releases WHERE NOT hidden) AND vid IN(SELECT id FROM vn WHERE NOT hidden)' },
    rlists              => { where => 'EXISTS(SELECT 1 FROM releases r'
                                                    .' JOIN releases_vn rv ON rv.id = r.id'
                                                    .' JOIN vn v ON v.id = rv.vid'
                                                    .' JOIN ulist_vns uv ON uv.vid = rv.vid'
                                                   .' WHERE r.id = rlists.rid AND uv.uid = rlists.uid AND NOT r.hidden AND NOT v.hidden AND NOT uv.c_private)' },
    staff               => { where => 'NOT hidden' },
    staff_alias         => { where => 'id IN(SELECT id FROM staff WHERE NOT hidden)' },
    tags                => { where => 'NOT hidden' },
    tags_parents        => { where => 'id IN(SELECT id FROM tags WHERE NOT hidden)' },
    tags_vn             => { where => 'tag IN(SELECT id FROM tags WHERE NOT hidden) AND vid IN(SELECT id FROM vn WHERE NOT hidden)', order => 'tag, vid, uid, date' },
    traits              => { where => 'NOT hidden' },
    traits_parents      => { where => 'id IN(SELECT id FROM traits WHERE NOT hidden)' },
    ulist_labels        => { where => 'NOT private AND EXISTS(SELECT 1 FROM ulist_vns uv JOIN vn v ON v.id = uv.vid
                                        WHERE NOT v.hidden AND uv.labels && ARRAY[ulist_labels.id] AND ulist_labels.uid = uv.uid)' },
    ulist_vns           => { sql => $sql_ulist_vns },
    users               => { where => 'id IN(SELECT DISTINCT uid FROM ulist_vns WHERE NOT c_private)'
                                 .' OR id IN(SELECT DISTINCT uid FROM tags_vn)'
                                 .' OR id IN(SELECT DISTINCT uid FROM image_votes)'
                                 .' OR id IN(SELECT DISTINCT uid FROM vn_length_votes WHERE NOT private)' },
    vn                  => { where => 'NOT hidden' },
    vn_anime            => { where => 'id IN(SELECT id FROM vn WHERE NOT hidden)' },
    vn_editions         => { where => 'id IN(SELECT id FROM vn WHERE NOT hidden)' },
    vn_relations        => { where => 'id IN(SELECT id FROM vn WHERE NOT hidden)' },
    vn_screenshots      => { where => 'id IN(SELECT id FROM vn WHERE NOT hidden)' },
    vn_seiyuu           => { where => 'id IN(SELECT id FROM vn WHERE NOT hidden)'
                                .' AND aid IN(SELECT sa.aid FROM staff_alias sa JOIN staff s ON s.id = sa.id WHERE NOT s.hidden)'
                                .' AND cid IN(SELECT id FROM chars WHERE NOT hidden)' },
    vn_staff            => { where => 'id IN(SELECT id FROM vn WHERE NOT hidden) AND aid IN(SELECT sa.aid FROM staff_alias sa JOIN staff s ON s.id = sa.id WHERE NOT s.hidden)'
                           , order => 'id, eid, aid, role' },
    vn_titles           => { where => 'id IN(SELECT id FROM vn WHERE NOT hidden)' },
    vn_length_votes     => { where => 'vid IN(SELECT id FROM vn WHERE NOT hidden) AND NOT private'
                           , order => 'vid, uid' },
    wikidata            => { where => q{id IN(SELECT l_wikidata FROM producers WHERE NOT hidden
                                        UNION SELECT l_wikidata FROM staff WHERE NOT hidden
                                        UNION SELECT l_wikidata FROM vn WHERE NOT hidden)} },
);

my @tables = map +{ name => $_, %{$tables{$_}} }, sort keys %tables;
my $schema = VNDB::Schema::schema;
my $types = VNDB::Schema::types;
my $references = VNDB::Schema::references;

my $db = DBI->connect('dbi:Pg:dbname=vndb', 'vndb', undef, { RaiseError => 1, AutoCommit => 0 });
$db->do('SET TIME ZONE +0');


sub consistent_snapshot {
    my($func) = @_;
    my($standby) = $db->selectrow_array('SELECT pg_is_in_recovery()');
    if($standby) {
        $db->do('SELECT pg_wal_replay_pause()');
    } else {
        $db->rollback;
        $db->do('SET TRANSACTION ISOLATION LEVEL SERIALIZABLE');
    }
    eval { $func->() };
    warn $@ if length $@;
    $db->do('SELECT pg_wal_replay_resume()') if $standby;
}


sub table_order {
    my $s = $schema->{$_[0]};
    my $c = $tables{$_[0]};
    my $o = $s->{primary} ? join ', ', map "\"$_\"", $s->{primary}->@* : $c ? $c->{order} : '';
    $o ? "ORDER BY $o" : '';
}


sub export_timestamp {
    my $dest = shift;
    open my $F, '>', $dest;
    printf $F "%s\n", $db->selectrow_array('SELECT date_trunc(\'second\', NOW())');
}


sub export_table {
    my($dest, $table) = @_;

    my $schema = $schema->{$table->{name}};
    my @cols = grep $_->{pub}, @{$schema->{cols}};
    die "No columns to export for table '$table->{name}'\n" if !@cols;;

    my $fn = "$dest/$table->{name}";

    my $sql = $table->{sql} // do {
        # Truncate all timestamptz columns to a day, to avoid leaking privacy-sensitive info.
        my $cols = join ', ', map $_->{type} eq 'timestamptz' ? "date_trunc('day', \"$_->{name}\")" : qq{"$_->{name}"}, @cols;
        my $where = $table->{where} ? "WHERE $table->{where}" : '';
        my $order = table_order $table->{name};
        die "Table '$table->{name}' is missing an ORDER BY clause\n" if !$order;
        qq{SELECT $cols FROM "$table->{name}" $where $order}
    };

    my $start = time;
    $db->do(qq{COPY ($sql) TO STDOUT});
    open my $F, '>:utf8', $fn;
    my $v;
    print $F $v while($db->pg_getcopydata($v) >= 0);
    close $F;

    #printf "# Dumped %s in %.3fs\n", $table->{name}, time-$start;

    open $F, '>', "$fn.header";
    print $F join "\t", map $_->{name}, @cols;
    print $F "\n";
    close $F;
}


sub export_import_script {
    my $dest = shift;
    open my $F, '>', $dest;
    print $F <<'    _' =~ s/^    //mgr;
    -- This script will create the necessary tables and import all data into an
    -- existing PostgreSQL database.
    --
    -- Usage:
    --   Run a 'CREATE DATABASE $database' somewhere.
    --   psql -U $user $database -f import.sql
    --
    -- The imported database does not include any indices, other than primary keys.
    -- You may want to create some indices by hand to speed up complex queries.

    -- Uncomment to import the schema and data into a separate namespace:
    --CREATE SCHEMA vndb;
    --SET search_path TO vndb;

    -- 'vndbid' is a custom base type used in the VNDB codebase, but it's safe to treat
    -- it as just text. If you want to use the proper type, load sql/vndbid.sql from
    -- the VNDB source code into your database and comment out the following line.
    -- (or ignore the error message about 'vndbid' already existing)
    CREATE DOMAIN vndbid AS text;
    _

    print $F "\n\n";
    my %types = map +($_->{type}, 1), grep $_->{pub}, map @{$schema->{$_->{name}}{cols}}, @tables;
    print $F "$types->{$_}{decl}\n" for (sort grep $types->{$_}, keys %types);

    for my $table (@tables) {
        my $schema = $schema->{$table->{name}};
        my @primary = grep { my $n=$_; !!grep $_->{name} eq $n && $_->{pub}, $schema->{cols}->@* } ($schema->{primary}||[])->@*;
        print $F "\n";
        print $F "CREATE TABLE $table->{name} (\n";
        print $F join ",\n", map "  $_->{decl}" =~ s/ serial/ integer/ir =~ s/ +(?:check|constraint|default) +.*//ir, grep $_->{pub}, @{$schema->{cols}};
        print $F ",\n  PRIMARY KEY(".join(', ', map "$_", @primary).")" if @primary;
        print $F "\n);\n";
    }

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
}


sub export_db {
    my $dest = shift;

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

    cp "$ROOT/util/dump/$_", "${dest}_dir/$_" for @static;

    export_timestamp "${dest}_dir/TIMESTAMP";
    export_table "${dest}_dir/db", $_ for @tables;
    export_import_script "${dest}_dir/import.sql";

    #print "# Compressing\n";
    `tar -cf "$dest" -I 'zstd -7' --sort=name -C "${dest}_dir" @static import.sql TIMESTAMP db`;
    rmtree "${dest}_dir";
}


# Copy file while retaining access/modification times
sub cp_p {
    my($from, $to) = @_;
    cp $from, $to;
    utime @{ [stat($from)] }[8,9], $to;
}


# XXX: This does not include images that are linked from descriptions; May want to borrow from util/unusedimages.pl to find those.
sub export_img {
    my $dest = shift;

    no autodie;
    mkdir ${dest};
    mkdir sprintf '%s/%s', $dest, $_ for qw/ch cv sf st/;
    mkdir sprintf '%s/%s/%02d', $dest, $_->[0], $_->[1] for map +([ch=>$_], [cv=>$_], [sf=>$_], [st=>$_]), 0..99;

    cp_p "$ROOT/util/dump/LICENSE-ODBL.txt", "$dest/LICENSE-ODBL.txt";
    cp_p "$ROOT/util/dump/README-img.txt", "$dest/README.txt";
    export_timestamp "$dest/TIMESTAMP";

    my %scr;
    my %dir = (ch => {}, cv => {}, sf => \%scr, st => \%scr);
    $dir{sf}{$_->[0]} = 1 for $db->selectall_array("SELECT vndbid_num(scr) FROM vn_screenshots WHERE $tables{vn_screenshots}{where}");
    $dir{cv}{$_->[0]} = 1 for $db->selectall_array("SELECT vndbid_num(image) FROM vn WHERE image IS NOT NULL AND $tables{vn}{where}");
    $dir{ch}{$_->[0]} = 1 for $db->selectall_array("SELECT vndbid_num(image) FROM chars WHERE image IS NOT NULL AND $tables{chars}{where}");
    $db->rollback;
    undef $db;

    find {
        no_chdir => 1,
        wanted => sub {
            unlink $File::Find::name or warn "Unable to unlink $File::Find::name: $!\n"
                if $File::Find::name =~ m{(cv|ch|sf|st)/[0-9][0-9]/([0-9]+)\.jpg$} && !$dir{$1}{$2};
        }
    }, $dest;

    for my $d (keys %dir) {
        for my $i (keys %{$dir{$d}}) {
            my $f = sprintf('%s/%02d/%d.jpg', $d, $i % 100, $i);
            link "$ROOT/static/$f", "$dest/$f" or warn "Unable to link $f: $!\n" if !-e "$dest/$f";
        }
    }
}


sub export_data {
    my $dest = shift;
    my $F = *STDOUT;
    open $F, '>', $dest if $dest ne '-';
    binmode($F, ":utf8");
    select $F;
    print "\\set ON_ERROR_STOP 1\n";
    print "\\i sql/util.sql\n";
    print "\\i sql/schema.sql\n";
    # Would be nice if VNDB::Schema could list sequences, too.
    my @seq = sort @{ $db->selectcol_arrayref(
        "SELECT oid::regclass::text FROM pg_class WHERE relkind = 'S' AND relnamespace = 'public'::regnamespace"
    ) };
    printf "SELECT setval('%s', %d);\n", $_, $db->selectrow_array("SELECT last_value FROM \"$_\"", {}) for @seq;
    for my $t (sort { $a->{name} cmp $b->{name} } values %$schema) {
        my $cols = join ',', map "\"$_->{name}\"", grep $_->{decl} !~ /\sGENERATED\s/, $t->{cols}->@*;
        my $order = table_order $t->{name};
        print "\nCOPY \"$t->{name}\" ($cols) FROM STDIN;\n";
        $db->do("COPY (SELECT $cols FROM \"$t->{name}\" $order) TO STDOUT");
        my $v;
        print $v while($db->pg_getcopydata($v) >= 0);
        print "\\.\n";
    }
    print "\\i sql/func.sql\n";
    print "\\i sql/editfunc.sql\n";
    print "\\i sql/tableattrs.sql\n";
    print "\\i sql/triggers.sql\n";
    print "\\set ON_ERROR_STOP 0\n";
    print "\\i sql/perms.sql\n";
}


sub export_votes {
    my $dest = shift;
    require PerlIO::gzip;

    open my $F, '>:gzip:utf8', $dest;
    $db->do(q{COPY (
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
    print $F $v while($db->pg_getcopydata($v) >= 0);
}


sub export_tags {
    my $dest = shift;
    require JSON::XS;
    require PerlIO::gzip;

    my $lst = $db->selectall_arrayref(q{
        SELECT vndbid_num(id) AS id, name, description, searchable, applicable, c_items AS vns, cat, alias,
          (SELECT string_agg(vndbid_num(parent)::text, ',' ORDER BY main desc, parent) FROM tags_parents tp WHERE tp.id = t.id) AS parents
        FROM tags t WHERE NOT hidden ORDER BY id
    }, { Slice => {} });
    for(@$lst) {
      $_->{id} *= 1;
      $_->{meta} = !$_->{searchable} ? JSON::XS::true() : JSON::XS::false(); # For backwards compat
      $_->{searchable} = $_->{searchable} ? JSON::XS::true() : JSON::XS::false();
      $_->{applicable} = $_->{applicable} ? JSON::XS::true() : JSON::XS::false();
      $_->{vns} *= 1;
      $_->{aliases} = [ split /\n/, delete $_->{alias} ];
      $_->{parents} = [ map $_*1, split /,/, ($_->{parents}||'') ];
    }

    open my $F, '>:gzip:utf8', $dest;
    print $F JSON::XS->new->canonical->encode($lst);
}


sub export_traits {
    my $dest = shift;
    require JSON::XS;
    require PerlIO::gzip;

    my $lst = $db->selectall_arrayref(q{
        SELECT vndbid_num(id) AS id, name, alias AS aliases, description, searchable, applicable, c_items AS chars,
               (SELECT string_agg(vndbid_num(parent)::text, ',' ORDER BY main desc, parent) FROM traits_parents tp WHERE tp.id = t.id) AS parents
        FROM traits t WHERE NOT hidden ORDER BY id
    }, { Slice => {} });
    for(@$lst) {
      $_->{id} *= 1;
      $_->{meta} = $_->{searchable} ? JSON::XS::true() : JSON::XS::false(); # For backwards compat
      $_->{searchable} = $_->{searchable} ? JSON::XS::true() : JSON::XS::false();
      $_->{applicable} = $_->{applicable} ? JSON::XS::true() : JSON::XS::false();
      $_->{chars} *= 1;
      $_->{aliases} = [ split /\r?\n/, ($_->{aliases}||'') ];
      $_->{parents} = [ map $_*1, split /,/, ($_->{parents}||'') ];
    }

    open my $F, '>:gzip:utf8', $dest;
    print $F JSON::XS->new->canonical->encode($lst);
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
