package VNWeb::DB;

use v5.36;
use FU;
use FU::SQL;
use Carp 'confess';
use Exporter 'import';
use VNDB::Schema;
use VNDB::Config;
use experimental 'builtin'; # for is_bool

our @EXPORT = qw/
    global_settings
    sql_like USER
    db_maytimeout db_entry db_edit
/;




# Escape a string to be used as a literal match in a LIKE pattern.
sub sql_like :prototype($) { $_[0] =~ s/([%_\\])/\\$1/rg }

# Returns a list of column names to fetch for displaying a username with HTML::user_().
# Arguments: Name of the 'users' table (default: 'u'), prefix for the fetched fields (default: 'user_').
sub USER {
    my $tbl = shift||'u';
    my $prefix = shift||'user_';
    RAW join ', ',
       "$tbl.id              as ${prefix}id",
       "$tbl.username        as ${prefix}name",
       "$tbl.support_can     as ${prefix}support_can",
       "$tbl.support_enabled as ${prefix}support_enabled",
       "$tbl.uniname_can     as ${prefix}uniname_can",
       "$tbl.uniname         as ${prefix}uniname",
       fu->{auth} && VNWeb::Auth::auth()->isMod ? (
           "$tbl.perm_board      as ${prefix}perm_board",
           "$tbl.perm_edit       as ${prefix}perm_edit"
       ) : (),
}

# Returns a (potentially cached) version of the global_settings table.
sub global_settings {
    fu->{global_settings} //= fu->sql('SELECT * FROM global_settings')->rowh;
}


# fu->enrich(%opt, $sql, $list):
#
#   $list:
#       Array of hashes to enrich.
#   $sql:
#       String or FU::Sql object to which an appropriate IN() clause is appended.
#       Or: Subroutine ref returning a string or FU::Sql object containing IN($_).
#       The SQL statement must return the 'key' back as first column.
#   $opt{key}:
#       Hash key to take from objects in $list, defaults to 'id'.
#
# Action:
#
#   $opt{merge}:
#       When set, the (non-key) columns returned by $sql are merged into the
#       objects in $list. $sql must not return more than 1 row per id. Columns
#       for missing rows are set to undef.
#
#   $opt{set}:
#       Set the given field to the value of the second column in $sql.
#
#   $opt{seth}:
#       Set the given field to the row hash.
#
#   $opt{aoh}:
#       Write an array of hashes to the specified field.
#
#   $opt{aov}:
#       Write an array of values.
#
# Based on ideas described in https://dev.yorhel.nl/doc/sqlobject
sub FU::obj::enrich {
    my $lst = pop;
    my $sql = pop;
    my %opt = @_[1..$#_];
    my $key = $opt{key} || 'id';

    local $_ = [ map $_->{$key}//(), @$lst ];
    return if !@$_;
    my $st = fu->SQL(ref $sql eq 'CODE' ? $sql->() : (ref $sql ? $sql : RAW($sql), IN $_));

    if ($opt{merge}) {
        my $r = $st->kva;
        my @col = map $_->{name}, $st->columns->@*;
        shift @col;
        for (@$lst) {
            my $o = $r->{ my $x = $_->{$key} };
            @{$_}{@col} = $o ? @$o : map undef, 0..$#col;
        }

    } elsif ($opt{set}) {
        my $field = $opt{set};
        my $r = $st->kvv;
        $_->{$field} = $r->{ my $x = $_->{$key} } for @$lst;

    } elsif ($opt{seth}) {
        my $field = $opt{seth};
        my $r = $st->kvh;
        $_->{$field} = $r->{ my $x = $_->{$key} } for (grep defined $_->{$key}, @$lst);

    } elsif ($opt{aoh}) {
        my $field = $opt{aoh};
        my @col = map $_->{name}, $st->columns->@*;
        shift @col;
        my %r;
        for my $row ($st->alla->@*) { # an $st->kvaoh() would be useful here
            push $r{$row->[0]}->@*, { map +($col[$_], $row->[$_+1]), 0..$#col };
        }
        $_->{$field} = $r{ my $x = $_->{$key} } || [] for @$lst;

    } elsif ($opt{aov}) {
        my $field = $opt{aov};
        my %r;
        for my ($k,$v) ($st->flat->@*) {
            push $r{$k}->@*, $v;
        }
        $_->{$field} = $r{ my $x = $_->{$key} } || [] for @$lst;

    } else {
        confess 'Unknown enrich action';
    }
}



# Run the given subroutine inside a savepoint and capture an SQL timeout.
# Returns false and logs a warning on timeout.
sub db_maytimeout :prototype(&) ($f) {
    fu->db->exec('SAVEPOINT maytimeout');
    my $r = eval { $f->(); 1 };

    if(!$r && $@ =~ /canceling statement due to statement timeout/) {
        fu->db->exec('ROLLBACK TO SAVEPOINT maytimeout');
        warn "Query timed out\n";
        return 0;
    }
    confess $@ if !$r;
    fu->db->exec('RELEASE SAVEPOINT maytimeout');
    1;
}



# Database entry API: Intended to provide a low-level read/write interface for
# versioned database entires. The same data structure is used for reading and
# updating entries, and should support easy diffing/comparison.
# Not very convenient for general querying & searching, those still need custom
# queries.


# Hash table, something like:
# {
#   v => {
#       prefix => 'vn',
#       base => { .. 'vn_hist' schema }
#       tables => {
#           anime => { .. 'vn_anime_hist' schema }
#       },
#   }, ..
# }
my $entry_types = do {
    my $schema = VNDB::Schema::schema;
    my %types = map +($_->{dbentry_type}, { prefix => $_->{name} }), grep $_->{dbentry_type}, values %$schema;
    for my $t (values %$schema) {
        my $n = $t->{name};
        my($type) = grep $n =~ /^$_->{prefix}_/, values %types;
        next if !$type || $n !~ s/^$type->{prefix}_?(.*)_hist$/$1/;
        if($n eq '') { $type->{base}       = $t }
        else         { $type->{tables}{$n} = $t }
    }
    \%types;
};


# Automatically enrich selected tables, arg is: [ $select, $joins, $orderby ]
# (Enriching the main entry's table is not yet supported, just data tables for now)
my %enrich = (
    releases_extlinks   => [ 'l.site, l.value, l.data, l.price', RAW('JOIN extlinks l ON l.id = x.link'), 'l.site, l.value' ],
    producers_extlinks  => [ 'l.site, l.value, l.data, l.price', RAW('JOIN extlinks l ON l.id = x.link'), 'l.site, l.value' ],
    staff_extlinks      => [ 'l.site, l.value, l.data, l.price', RAW('JOIN extlinks l ON l.id = x.link'), 'l.site, l.value' ],
    vn_extlinks         => [ 'l.site, l.value, l.data, l.price', RAW('JOIN extlinks l ON l.id = x.link'), 'l.site, l.value' ],

    chars_vns           => [
        'v.title, r.title AS rtitle, v.hidden',
        sub { SQL 'JOIN', VNWeb::TitlePrefs::VNT(), 'v ON v.id = x.vid LEFT JOIN', VNWeb::TitlePrefs::RELEASEST(), 'r ON r.id = x.rid' },
        'v.c_released, v.sorttitle, r.released, x.vid, x.rid' ],

    staff_alias         => [ undef, undef, 'x.aid' ],

    releases_producers  => [ 'p.title', sub { SQL 'JOIN', VNWeb::TitlePrefs::PRODUCERST(), 'p ON p.id = x.pid' }, 'p.sorttitle, x.pid' ],
    releases_vn         => [ 'v.title, v.hidden', sub { SQL 'JOIN', VNWeb::TitlePrefs::VNT(), 'v ON v.id = x.vid' }, 'v.sorttitle, x.vid' ],
    releases_supersedes => [ 'r.title, r.released, r.hidden', sub { SQL 'JOIN', VNWeb::TitlePrefs::RELEASEST(), 'r ON r.id = x.rid' }, 'r.released, x.rid' ],
    releases_drm        => [ 'd.name, '.join(',', keys %VNDB::Types::DRM_PROPERTY), RAW('JOIN drm d ON d.id = x.drm'), 'x.drm <> 0, d.name' ],
    releases_media      => [ undef, undef, 'x.medium, x.qty' ],
    releases_titles     => [ undef, undef, 'x.lang' ],
    releases_images     => [ undef, undef, 'x.itype, x.lang, x.vid, x.img' ],
    releases_platforms  => [ undef, undef, 'x.platform' ],

    vn_anime            => [ 'a.title_romaji, a.title_kanji, a.year, a.type, a.ann_id, a.mal_id, a.lastfetch', RAW('JOIN anime a ON a.id = x.aid'), 'a.year, a.title_romaji, x.aid' ],
    vn_staff            => [ 's.id AS sid, s.title', sub { SQL 'LEFT JOIN', VNWeb::TitlePrefs::STAFF_ALIAST(), 's ON s.aid = x.aid' }, 'x.eid NULLS FIRST, s.sorttitle, x.aid, x.role' ],
    vn_seiyuu           => [
        's.id AS sid, s.title, c.title AS char_title',
        sub { SQL 'LEFT JOIN', VNWeb::TitlePrefs::STAFF_ALIAST(), 's ON s.aid = x.aid JOIN', VNWeb::TitlePrefs::CHARST(), 'c ON c.id = x.cid' },
        'x.aid, x.cid, x.note' ],
    vn_screenshots      => [ undef, undef, 'x.scr' ],
    vn_titles           => [ undef, undef, 'NOT x.official, x.lang' ],
    vn_editions         => [ undef, undef, 'x.lang NULLS FIRST, NOT x.official, x.name' ],
    vn_relations        => [ 'v.title, v.c_released', sub { SQL 'JOIN', VNWeb::TitlePrefs::VNT(), 'v ON v.id = x.vid' }, 'NOT x.official, v.c_released, v.sorttitle, x.vid' ],

    producers_relations => [ 'p.title', sub { SQL 'JOIN', VNWeb::TitlePrefs::PRODUCERST(), 'p ON p.id = x.pid' }, 'p.sorttitle, x.pid' ],

    tags_parents        => [ 't.name', RAW('JOIN tags t ON t.id = x.parent'), 't.name, x.parent' ],

    traits_parents      => [ 't.name, g.name AS group', RAW('JOIN traits t ON t.id = x.parent LEFT JOIN traits g ON g.id = t.gid'), 't.name, x.parent' ],
);


# Returns everything for a specific entry ID. The top-level hash also includes
# the following keys:
#
#   id, chid, chrev, maxrev, hidden, locked, entry_hidden, entry_locked
#
# (Ordering of arrays can be specified in %enrich above)
sub db_entry($id, $rev=0) {
    my $t = $entry_types->{ substr $id, 0, 1 }||confess;

    return undef if config->{moe} && $rev;
    my $entry = fu->sql('
        WITH maxrev (maxrev) AS (SELECT MAX(rev) FROM changes WHERE itemid = $1)
        SELECT c.itemid AS id, c.id AS chid, c.rev AS chrev, c.ihid AS hidden, c.ilock AS locked
             , x.hidden AS entry_hidden, x.locked AS entry_locked, maxrev
          FROM maxrev, changes c, '.($t->{base}{name} =~ s/_hist$//r).' x
         WHERE c.itemid = $1 AND x.id = $1 AND c.rev = '.($rev ? '$2' : 'maxrev'),
         $id, $rev || ()
    )->rowh or return undef;

    # Fetch data from the main entry tables if rev == maxrev, from the _hist
    # tables otherwise. This should improve caching a bit.
    my sub data_table($tbl, @join) {
        ref $_ eq 'CODE' && ($_ = $_->()) for @join;
        $entry->{chrev} == $entry->{maxrev} ? SQL RAW($tbl =~ s/_hist$//r), 'x', @join, 'WHERE x.id =', $id
                                            : SQL RAW($tbl), 'x', @join, 'WHERE x.chid =', $entry->{chid}
    }

    my $toplvl = fu->SQL(
        SELECT => RAW(join ', ', map $_->{name}, grep $_->{name} ne 'chid', $t->{base}{cols}->@*),
        FROM   => data_table $t->{base}{name}
    )->rowh or return undef;
    %$entry = (%$entry, %$toplvl);

    while(my($name, $tbl) = each $t->{tables}->%*) {
        my $enrich = $enrich{ $tbl->{name} =~ s/_hist$//r } || [];
        $entry->{$name} = fu->SQL(
            SELECT => RAW(join ', ',
                (map "x.$_->{name}", grep $_->{name} ne 'chid', $tbl->{cols}->@*),
                $enrich->[0] || (),
            ),
            FROM   => data_table($tbl->{name}, $enrich->[1] || ()),
            $enrich->[2] ? ('ORDER BY', RAW $enrich->[2]) : (),
        )->allh;
    }
    $entry
}


# Edit or create an entry, usage:
#   ($id, $chid, $rev) = db_edit $type, $id, $data, $uid;
#
# $id should be undef to create a new entry.
# $uid should be undef to use the currently logged in user.
# $data should have the same format as returned by db_entry(), but instead with
# the following additional keys in the top-level hash:
#
#   hidden, locked, editsum
sub db_edit($type, $id, $data, $uid=undef) {
    $id ||= undef;
    my $t = $entry_types->{$type}||die;

    fu->sql("SELECT edit_${type}_init(\$1, (SELECT MAX(rev) FROM changes WHERE itemid = \$1))", $id)->exec;
    fu->SQL('UPDATE edit_revision', SET {
        requester => $uid // scalar VNWeb::Auth::auth()->uid(),
        comments  => $data->{editsum},
        ihid      => $data->{hidden},
        ilock     => $data->{locked},
    })->exec;

    {
        my $base = $t->{base}{name} =~ s/_hist$//r;
        fu->SQL(RAW("UPDATE edit_${base}"), SET {
            map +($_->{name}, $data->{$_->{name}}), grep $_->{name} ne 'chid' && exists $data->{$_->{name}}, $t->{base}{cols}->@*
        })->exec;
    }

    for my ($name, $tbl) ($t->{tables}->%*) {
        my $base = $tbl->{name} =~ s/_hist$//r;
        fu->sql("DELETE FROM edit_${base}")->exec;
        for my $r ($data->{$name}->@*) {
            fu->SQL(RAW("INSERT INTO edit_${base}"), VALUES {
                map +($_->{name}, $r->{$_->{name}}), grep $_->{name} ne 'chid' && exists $r->{$_->{name}}, $tbl->{cols}->@*
            })->exec;
        }
    }

    fu->sql("SELECT * FROM edit_${type}_commit()")->rowh;
}

1;
