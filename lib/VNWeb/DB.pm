package VNWeb::DB;

use v5.36;
use FU;
use FU::SQL;
use SQL::Interp ':all';
use Carp 'confess';
use Exporter 'import';
use VNDB::Schema;
use VNDB::Config;
use experimental 'builtin'; # for is_bool

our @EXPORT = qw/
    sql
    global_settings
    sql_join sql_comma sql_and sql_or sql_array sql_func sql_fromtime sql_totime sql_like sql_user
    USER
    enrich enrich_merge enrich_flatten enrich_obj
    db_maytimeout db_entry db_edit
/;



# TUWF db* methods, should migrate to directly using fu->q() instead.
sub _sqlhelper($type, $sql, @params) {
    my $r;
    for (@params) { $_ ||= 0 if builtin::is_bool($_) }
    my $n = 0;
    my $st = fu->sql($sql =~ s/\?/'$'.++$n/egr, @params)->cache(0)->text_params;
    return $type == 1 ? $st->flat->[0] : # $st->val throws if the query returns multiple rows/columns
           $type == 2 ? ($st->rowh || {}) :
           $type == 3 ? $st->allh : $st->exec;
}

sub FU::obj::dbExec { shift; _sqlhelper(0, @_) }
sub FU::obj::dbVal  { shift; _sqlhelper(1, @_) }
sub FU::obj::dbRow  { shift; _sqlhelper(2, @_) }
sub FU::obj::dbAll  { shift; _sqlhelper(3, @_) }
sub FU::obj::dbPage($s, $o, $q, @a) {
    my $r = $s->dbAll($q.' LIMIT ? OFFSET ?', @a, $o->{results}+(wantarray?1:0), $o->{results}*($o->{page}-1));
    return $r if !wantarray;
    return ($r, 0) if $#$r != $o->{results};
    pop @$r;
    return ($r, 1);
}


# Test for potential SQL injection and warn about it. This will cause some
# false positives.
# The heuristic is pretty simple: Just check if there's an integer in the SQL
# statement. SQL injection through strings is likely to be caught much earlier,
# since that will generate a syntax error if the string is not properly escaped
# (and who'd put effort into escaping strings when placeholders are easier?).
sub interp_warn {
    my @r;
    confess $@ if !eval { @r = sql_interp @_ };
    # 0 and 1 aren't interesting, "SELECT 1" is a common pattern and so is "x > 0".
    # '{7}' is commonly used in ulist filtering and r18/api2 are a valid database identifiers.
    #warn "Possible SQL injection in '$r[0]'" if fu->debug && ($r[0] =~ s/(?:r18|\{7\}|api2)//rg) =~ /[2-9]/;
    return @r;
}

# SQL::Interp wrappers around TUWF's db* methods.  These do not work with
# sql_type(). Should migrate to FU::Pg instead.
sub FU::obj::dbExeci { shift; _sqlhelper(0, interp_warn @_) }
sub FU::obj::dbVali  { shift; _sqlhelper(1, interp_warn @_) }
sub FU::obj::dbRowi  { shift; _sqlhelper(2, interp_warn @_) }
sub FU::obj::dbAlli  { shift; _sqlhelper(3, interp_warn @_) }
sub FU::obj::dbPagei { shift->dbPage(shift, interp_warn @_) }




# sql_* are macros for SQL::Interp use

# join(), but for sql objects.
sub sql_join {
    my $sep = shift;
    my @args = map +($sep, $_), @_;
    sql @args[1..$#args];
}

# Join multiple arguments together with a comma, for use in a SELECT or IN
# clause or function arguments.
sub sql_comma { sql_join ',', @_ }

sub sql_and   { @_ ? sql_join 'AND', map sql('(', $_, ')'), @_ : sql '1=1' }
sub sql_or    { @_ ? sql_join 'OR',  map sql('(', $_, ')'), @_ : sql '1=0' }

# Construct a PostgreSQL array type from the function arguments.
sub sql_array { 'ARRAY[', sql_comma(map \$_, @_), ']' }

# Call an SQL function
sub sql_func {
    my($funcname, @args) = @_;
    sql $funcname, '(', sql_comma(@args), ')';
}

# Convert a Perl time value (UNIX timestamp) into a Postgres timestamp
sub sql_fromtime :prototype($) {
    sql_func to_timestamp => \$_[0];
}

# Convert a Postgres timestamp into a Perl time value
sub sql_totime :prototype($) {
    sql "extract('epoch' from ", $_[0], ')::float8';
}

# Escape a string to be used as a literal match in a LIKE pattern.
sub sql_like :prototype($) {
    $_[0] =~ s/([%_\\])/\\$1/rg
}

# Returns a list of column names to fetch for displaying a username with HTML::user_().
# Arguments: Name of the 'users' table (default: 'u'), prefix for the fetched fields (default: 'user_').
# (This function returns a plain string so that old non-SQL-Interp functions can also use it)
sub sql_user {
    my $tbl = shift||'u';
    my $prefix = shift||'user_';
    join ', ',
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

sub USER { RAW sql_user(@_) }

# Returns a (potentially cached) version of the global_settings table.
sub global_settings {
    fu->{global_settings} //= fu->sql('SELECT * FROM global_settings')->rowh;
}



# The enrich*() functions are based on https://dev.yorhel.nl/doc/sqlobject
# See that article for general usage information, the following is purely
# reference documentation:
#
# enrich $name, $key, $merge_col, $sql, @objects;
#
#   Add a $name field to each item in @objects,
#   Its value is a (possibly empty) array of hashes with data from $sql,
#
# enrich_flatten $name, $key, $merge_col, $sql, @objects;
#
#   Add a $name field to each item in @objects,
#   Its value is a (possibly empty) array of values from a single column from $sql,
#
# enrich_merge $key, $sql, @objects;
#
#   Merge all columns returned by $sql into @objects;
#
# enrich_obj $key, $merge_col, $sql, @objects;
#
#   Replace all non-undef $key fields in @objects with an object returned by $sql.
#
# Arguments:
#
#   $key is the field in @objects used in the IN clause of $sql,
#
#   $merge_col is the column name returned by $sql and compared against the
#     values of the $key field.
#     (enrich_merge() requires that the column name is equivalent to $key)
#
#   $sql is the query to be executed, can be either:
#     - A string or sql() object, in which case it should end with ' IN' so
#       that the list of identifiers can be appended to it.
#     - A subroutine, in which case the array of identifiers is given as first
#       argument. The sub should return an sql() object.
#
#   @objects is a list or array of hashrefs to be enriched.


# Helper function for the enrich functions below.
sub _enrich {
    my($merge, $key, $sql, @array) = @_;

    # 'flatten' the given array, so that you can also give arrayrefs as argument
    @array = map +(ref $_ eq 'ARRAY' ? @$_ : $_), @array;

    # Create a list of unique identifiers to fetch, do nothing if there's nothing to fetch
    my %ids = map defined($_->{$key}) ? ($_->{$key},1) : (), @array;
    return if !keys %ids;

    # Fetch the data
    $sql = ref $sql eq 'CODE' ? do { local $_ = [keys %ids]; sql $sql->($_) } : sql $sql, [keys %ids];
    my $data = fu->dbAlli($sql);

    # And merge
    $merge->($data, \@array);
}


sub enrich {
    my($name, $key, $merge_col, $sql, @array) = @_;
    _enrich sub {
        my($data, $array) = @_;
        my %ids = ();
        push $ids{ delete $_->{$merge_col} }->@*, $_ for @$data;
        $_->{$name} = $ids{ $_->{$key} }||[] for @$array;
    }, $key, $sql, @array;
}


sub enrich_merge {
    my($key, $sql, @array) = @_;
    _enrich sub {
        my($data, $array) = @_;
        my %ids = map +(delete($_->{$key}), $_), @$data;
        %$_ = (%$_, ($ids{ $_->{$key} }||{})->%*) for @$array;
    }, $key, $sql, @array;
}


sub enrich_flatten {
    my($name, $key, $merge_col, $sql, @array) = @_;
    _enrich sub {
        my($data, $array) = @_;
        my %ids = ();
        push $ids{ delete $_->{$merge_col} }->@*, values %$_ for @$data;
        $_->{$name} = $ids{ $_->{$key} }||[] for @$array;
    }, $key, $sql, @array;
}


sub enrich_obj {
    my($key, $merge_col, $sql, @array) = @_;
    _enrich sub {
        my($data, $array) = @_;
        my %ids = map +($_->{$merge_col}, $_), @$data;
        $_->{$key} = defined $_->{$key} ? $ids{ $_->{$key} } : undef for @$array;
    }, $key, $sql, @array;
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
            my $o = $r->{$_->{$key}};
            @{$_}{@col} = $o ? @$o : map undef, 0..$#col;
        }

    } elsif ($opt{set}) {
        my $field = $opt{set};
        my $r = $st->kvv;
        $_->{$field} = $r->{$_->{$key}} for @$lst;

    } elsif ($opt{seth}) {
        my $field = $opt{seth};
        my $r = $st->kvh;
        $_->{$field} = $r->{$_->{$key}} for (grep defined $_->{$key}, @$lst);

    # XXX: These do not support duplicate keys in $lst
    } elsif ($opt{aoh}) {
        my $field = $opt{aoh};
        my %objs = map { $_->{$field} = []; +($_->{$key}, $_) } @$lst;
        my $r = $st->alla;  # an $st->kvaoh() would be useful here
        my @col = map $_->{name}, $st->columns->@*;
        shift @col;
        for my $row (@$r) {
            push $objs{$row->[0]}{$field}->@*, { map +($col[$_], $row->[$_+1]), 0..$#col };
        }

    } elsif ($opt{aov}) {
        my $field = $opt{aov};
        my %objs = map { $_->{$field} = []; +($_->{$key}, $_) } @$lst;
        for my ($k,$v) ($st->flat->@*) {
            push $objs{$k}{$field}->@*, $v;
        }

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

    chars_vns           => [
        'v.title, r.title AS rtitle',
        sub { SQL 'JOIN', VNWeb::TitlePrefs::VNT(), 'v ON v.id = x.vid LEFT JOIN', VNWeb::TitlePrefs::RELEASEST(), 'r ON r.id = x.rid' },
        'v.c_released, v.sorttitle, r.released, x.vid, x.rid' ],

    staff_alias         => [ undef, undef, 'x.aid' ],

    releases_producers  => [ 'p.title', sub { SQL 'JOIN', VNWeb::TitlePrefs::PRODUCERST(), 'p ON p.id = x.pid' }, 'p.sorttitle, x.pid' ],
    releases_vn         => [ 'v.title', sub { SQL 'JOIN', VNWeb::TitlePrefs::VNT(), 'v ON v.id = x.vid' }, 'v.sorttitle, x.vid' ],
    releases_supersedes => [ 'r.title, r.released, r.hidden', sub { SQL 'JOIN', VNWeb::TitlePrefs::RELEASEST(), 'r ON r.id = x.rid' }, 'r.released, x.rid' ],
    releases_drm        => [ 'd.name, '.join(',', keys %VNDB::Types::DRM_PROPERTY), RAW('JOIN drm d ON d.id = x.drm'), 'x.drm <> 0, d.name' ],
    releases_media      => [ undef, undef, 'x.medium, x.qty' ],
    releases_titles     => [ undef, undef, 'x.lang' ],
    releases_images     => [ undef, undef, 'x.itype, x.lang, x.vid, x.img' ],
    releases_platforms  => [ undef, undef, 'x.platform' ],

    vn_anime            => [ 'a.title_romaji, a.title_kanji, a.year, a.type, a.ann_id, a.lastfetch', RAW('JOIN anime a ON a.id = x.aid'), 'a.year, a.title_romaji, x.aid' ],
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
    my $entry = fu->SQL('
        WITH maxrev (iid, maxrev) AS (SELECT itemid, MAX(rev) FROM changes WHERE itemid =', $id, 'GROUP BY itemid)
           , lastrev (entry_hidden, entry_locked) AS (SELECT ihid, ilock FROM maxrev, changes WHERE itemid = iid AND rev = maxrev)
        SELECT itemid AS id, id AS chid, rev AS chrev, ihid AS hidden, ilock AS locked, maxrev, entry_hidden, entry_locked
          FROM changes, maxrev, lastrev
         WHERE itemid = iid AND rev = ', $rev || 'maxrev'
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
