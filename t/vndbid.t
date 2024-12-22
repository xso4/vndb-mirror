#!/usr/bin/perl

# This test requires an initialized database.

use v5.36;
use Test::More;
use DBI;

my $db = eval {
    require VNDB::Config;
    DBI->connect(VNDB::Config::config()->{tuwf}{db_login}->@*, { RaiseError => 1, PrintError => 0 });
} || plan skip_all => "Unable to load config or connect to the database.";


my @alpha = ('a'..'z');
my @tags = (map +("$_", "$_$_", "$_$_$_"), @alpha);
my @ids = (map +("${_}1", "${_}1234567890", "${_}281474976710655"), @tags);

my @queries = (
    (map +("'$_'::vndbtag", $_), @tags),
    (map +("'$_'::vndbid", $_), @ids),

    "vndbtag ''", undef,
    "vndbtag 'aaaa'", undef,
    "vndbtag ' '", undef,
    "vndbtag ' a'", undef,
    "vndbtag 'a '", undef,

    "vndbid 'a'", undef,
    "vndbid '1'", undef,
    "vndbid 'a0'", undef,
    "vndbid 'a01'", undef,
    "vndbid ' a1'", undef,
    "vndbid 'a1 '", undef,
    "vndbid 'a-1'", undef,
    "vndbid 'a281474976710656'", undef,
    "vndbid 'A1'", undef,

    "vndbtag 'a'   <  'aa'", 1,
    "vndbtag 'a'   <= 'aa'", 1,
    "vndbtag 'a'   >  'aa'", 0,
    "vndbtag 'a'   >= 'aa'", 0,
    "vndbtag 'aa'  <  'aaa'", 1,
    "vndbtag 'aa'  <= 'aaa'", 1,
    "vndbtag 'aa'  >  'aaa'", 0,
    "vndbtag 'aa'  >= 'aaa'", 0,
    "vndbtag 'aaa' =  'aaa'", 1,
    "vndbtag 'aaa' <= 'aaa'", 1,
    "vndbtag 'aaa' >= 'aaa'", 1,
    "vndbtag 'aaa' <> 'aaa'", 0,
    "vndbtag 'b'   >  'a'", 1,
    "vndbtag 'z'   >  'y'", 1,
    "vndbtag 'bb'  >  'ba'", 1,
    "vndbtag 'bbb' >  'bab'", 1,
    "vndbtag 'bbb' >  'baa'", 1,

    "vndbid 'a1' <  'aa1'", 1,
    "vndbid 'a1' <= 'aa1'", 1,
    "vndbid 'a1' >  'aa1'", 0,
    "vndbid 'a1' >= 'aa1'", 0,
    "vndbid 'a1' =  'aa1'", 0,
    "vndbid 'a1' <> 'aa1'", 1,
    "vndbid 'a2' <  'a12'", 1,
    "vndbid 'a2' <= 'a12'", 1,
    "vndbid 'a2' >  'a12'", 0,
    "vndbid 'a2' >= 'a12'", 0,
    "vndbid 'a2' =  'a12'", 0,
    "vndbid 'a2' <> 'a12'", 1,
    "vndbid 'z3' <  'z3'", 0,
    "vndbid 'z3' <= 'z3'", 1,
    "vndbid 'z3' >  'z3'", 0,
    "vndbid 'z3' >= 'z3'", 1,
    "vndbid 'z3' =  'z3'", 1,
    "vndbid 'z3' <> 'z3'", 0,

    "vndbid('a', 1)", 'a1',
    "vndbid('zzz', 281474976710655)", 'zzz281474976710655',
    "vndbid('a', 0)", undef,
    "vndbid('a', -1)", undef,
    "vndbid('zzz', 281474976710656)", undef,

    "vndbid_type('a123')", 'a',
    "vndbid_type('abc123')", 'abc',
    "vndbid_istype('abc123', 'abc')", 1,
    "vndbid_num('a1')", 1,
    "vndbid_num('a281474976710655')", 281474976710655,
    "vndbid_max('x')", 'x281474976710655',
    "#vndbid 'x123'", 123,
    "~vndbid 'x123'", 'x',
    "vndbid 'x123' ^= 'x'", 1,
    "vndbid 'x123' ^= 'a'", 0,
    "vndbid 'xx123' ^= 'x'", 0,
    "vndbid 'x123' ^= 'xx'", 0,

    "'x1'::vndbid(1)", undef,
    "'x1'::vndbid(1,2)", undef,
    "'x1'::vndbid(aaaa)", undef,
    "'x1'::vndbid(x)", 'x1',
    "'x1'::vndbid(y)", undef,
    "'x1'::vndbid::vndbid(x)", 'x1',
    "'x1'::vndbid::vndbid(y)", undef,
    "'x1'::vndbid::vndbid(x)::vndbid(xy)", undef,
    "'x1'::vndbid(x) <> 'y1'::vndbid(y)", 1,
);

for my ($query, $exp) (@queries) {
    my $got;
    eval { ($got) = $db->selectrow_array("SELECT $query"); };
    is $got, $exp;
}



# Test binary send / recv.
# (Doesn't test the recv function on invalid inputs, sadly)

sub test_copy($type, $v) {
    $db->do("COPY (SELECT '$v'::$type) TO STDOUT (FORMAT binary)");
    my($bin, $x) = ('');
    $bin .= $x while $db->pg_getcopydata($x) >= 0;

    $db->do("COPY tmp_$type FROM STDIN (FORMAT binary)");
    $db->pg_putcopydata($bin);
    $db->pg_putcopyend;
    my ($got) = $db->selectrow_array("SELECT v FROM tmp_$type");
    is $got, $v;
    $db->do("TRUNCATE tmp_$type");
}

$db->do('CREATE TEMPORARY TABLE tmp_vndbtag (v vndbtag not null)');
$db->do('CREATE TEMPORARY TABLE tmp_vndbid (v vndbid not null)');
test_copy 'vndbtag', $_ for @tags;
test_copy 'vndbid', $_ for @ids;



# Test btree functions
# (Not exhaustive)

$db->do("INSERT INTO tmp_vndbtag
    SELECT (substr('abcdefghijklmnopqrstuvwxyz', a, 1)||substr('abcdefghijklmnopqrstuvwxyz', b, 1)||substr('abcdefghijklmnopqrstuvwxyz', c, 1))::vndbtag
      FROM generate_series(1, 26) a(a), generate_series(1, 26) b(b), generate_series(1, 26) c(c)") for (1..10);
$db->do('CREATE INDEX tmp_vndbtag_v ON tmp_vndbtag(v)');
like join("\n", map @$_, $db->selectall_array("EXPLAIN SELECT count(*) FROM tmp_vndbtag WHERE v = 'a'")), qr/tmp_vndbtag_v/;
is $db->selectrow_array("SELECT count(*) FROM tmp_vndbtag WHERE v = 'a'"), 0;
is $db->selectrow_array("SELECT count(*) FROM tmp_vndbtag WHERE v > 'yy' AND v < 'yz'"), 260;

$db->do("INSERT INTO tmp_vndbid SELECT vndbid(?, x) FROM generate_series(1, 1000) x(x)", {}, $_) for @tags;
$db->do('CREATE INDEX tmp_vndbid_v ON tmp_vndbid(v)');
like join("\n", map @$_, $db->selectall_array("EXPLAIN SELECT count(*) FROM tmp_vndbid WHERE v = 'ff123'")), qr/tmp_vndbid_v/;
is $db->selectrow_array("SELECT count(*) FROM tmp_vndbid WHERE v = 'ff123'"), 1;
is $db->selectrow_array("SELECT count(*) FROM tmp_vndbid WHERE v > 'ff1' AND v < 'ff100'"), 98;

# Yes, the ^= operator can use an index too!
like join("\n", map @$_, $db->selectall_array("EXPLAIN SELECT count(*) FROM tmp_vndbid WHERE v ^= 'ff'")), qr/tmp_vndbid_v/;
is $db->selectrow_array("SELECT count(*) FROM tmp_vndbid WHERE v ^= 'ff'"), 1000;

# But not in this context
unlike join("\n", map @$_, $db->selectall_array("EXPLAIN SELECT count(*) FROM tmp_vndbtag WHERE 'fff123' ^= v")), qr/tmp_vndbtag_v/;
is $db->selectrow_array("SELECT count(*) FROM tmp_vndbtag WHERE 'fff123' ^= v"), 10;

done_testing;
