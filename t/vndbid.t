#!/usr/bin/perl

# This test requires an initialized database.

use v5.36;
use Test::More;
use FU::Pg;

my $db = eval {
    require VNDB::Config;
    FU::Pg->connect(VNDB::Config::config()->{db_site});
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

    "vndbtag 'a'   <  'aa'", 't',
    "vndbtag 'a'   <= 'aa'", 't',
    "vndbtag 'a'   >  'aa'", 'f',
    "vndbtag 'a'   >= 'aa'", 'f',
    "vndbtag 'aa'  <  'aaa'", 't',
    "vndbtag 'aa'  <= 'aaa'", 't',
    "vndbtag 'aa'  >  'aaa'", 'f',
    "vndbtag 'aa'  >= 'aaa'", 'f',
    "vndbtag 'aaa' =  'aaa'", 't',
    "vndbtag 'aaa' <= 'aaa'", 't',
    "vndbtag 'aaa' >= 'aaa'", 't',
    "vndbtag 'aaa' <> 'aaa'", 'f',
    "vndbtag 'b'   >  'a'", 't',
    "vndbtag 'z'   >  'y'", 't',
    "vndbtag 'bb'  >  'ba'", 't',
    "vndbtag 'bbb' >  'bab'", 't',
    "vndbtag 'bbb' >  'baa'", 't',

    "vndbid 'a1' <  'aa1'", 't',
    "vndbid 'a1' <= 'aa1'", 't',
    "vndbid 'a1' >  'aa1'", 'f',
    "vndbid 'a1' >= 'aa1'", 'f',
    "vndbid 'a1' =  'aa1'", 'f',
    "vndbid 'a1' <> 'aa1'", 't',
    "vndbid 'a2' <  'a12'", 't',
    "vndbid 'a2' <= 'a12'", 't',
    "vndbid 'a2' >  'a12'", 'f',
    "vndbid 'a2' >= 'a12'", 'f',
    "vndbid 'a2' =  'a12'", 'f',
    "vndbid 'a2' <> 'a12'", 't',
    "vndbid 'z3' <  'z3'", 'f',
    "vndbid 'z3' <= 'z3'", 't',
    "vndbid 'z3' >  'z3'", 'f',
    "vndbid 'z3' >= 'z3'", 't',
    "vndbid 'z3' =  'z3'", 't',
    "vndbid 'z3' <> 'z3'", 'f',

    "vndbid('a', 1)", 'a1',
    "vndbid('zzz', 281474976710655)", 'zzz281474976710655',
    "vndbid('a', 0)", undef,
    "vndbid('a', -1)", undef,
    "vndbid('zzz', 281474976710656)", undef,

    "vndbid_type('a123')", 'a',
    "vndbid_type('abc123')", 'abc',
    "vndbid_istype('abc123', 'abc')", 't',
    "vndbid_num('a1')", 1,
    "vndbid_num('a281474976710655')", 281474976710655,
    "vndbid_max('x')", 'x281474976710655',
    "#vndbid 'x123'", 123,
    "~vndbid 'x123'", 'x',
    "vndbid 'x123' ^= 'x'", 't',
    "vndbid 'x123' ^= 'a'", 'f',
    "vndbid 'xx123' ^= 'x'", 'f',
    "vndbid 'x123' ^= 'xx'", 'f',

    "'x1'::vndbid(1)", undef,
    "'x1'::vndbid(1,2)", undef,
    "'x1'::vndbid(aaaa)", undef,
    "'x1'::vndbid(x)", 'x1',
    "'x1'::vndbid(y)", undef,
    "'x1'::vndbid::vndbid(x)", 'x1',
    "'x1'::vndbid::vndbid(y)", undef,
    "'x1'::vndbid::vndbid(x)::vndbid(xy)", undef,
    "'x1'::vndbid(x) <> 'y1'::vndbid(y)", 't',
);

for my ($query, $exp) (@queries) {
    my $got;
    eval { ($got) = $db->q("SELECT $query")->text->val; };
    is $got, $exp;
}



# Test binary send / recv.

$db->set_type(vndbid => 'bytea');
$db->set_type(vndbtag => 'bytea');

sub test_inout($type, $len, $v) {
    my $bin = $db->q("SELECT '$v'::$type")->val;
    is length($bin), $len;

    my $txt = $db->q("SELECT \$1::${type}::text", $bin)->val;
    is $txt, $v;
}

test_inout 'vndbtag', 2, $_ for @tags;
test_inout 'vndbid', 8, $_ for @ids;



# Test btree functions
# (Not exhaustive)

$db->exec('CREATE TEMPORARY TABLE tmp_vndbtag (v vndbtag not null)');
$db->exec("INSERT INTO tmp_vndbtag
    SELECT (substr('abcdefghijklmnopqrstuvwxyz', a, 1)||substr('abcdefghijklmnopqrstuvwxyz', b, 1)||substr('abcdefghijklmnopqrstuvwxyz', c, 1))::vndbtag
      FROM generate_series(1, 26) a(a), generate_series(1, 26) b(b), generate_series(1, 26) c(c)") for (1..10);
$db->exec('CREATE INDEX tmp_vndbtag_v ON tmp_vndbtag(v)');
like join("\n", $db->q("EXPLAIN SELECT count(*) FROM tmp_vndbtag WHERE v = 'a'")->flat->@*), qr/tmp_vndbtag_v/;
is $db->q("SELECT count(*) FROM tmp_vndbtag WHERE v = 'a'")->val, 0;
is $db->q("SELECT count(*) FROM tmp_vndbtag WHERE v > 'yy' AND v < 'yz'")->val, 260;

$db->exec('CREATE TEMPORARY TABLE tmp_vndbid (v vndbid not null)');
$db->q('INSERT INTO tmp_vndbid SELECT vndbid($1, x) FROM generate_series(1, 1000) x(x)', $_)->text->exec for @tags;
$db->exec('CREATE INDEX tmp_vndbid_v ON tmp_vndbid(v)');
like join("\n", $db->q("EXPLAIN SELECT count(*) FROM tmp_vndbid WHERE v = 'ff123'")->flat->@*), qr/tmp_vndbid_v/;
is $db->q("SELECT count(*) FROM tmp_vndbid WHERE v = 'ff123'")->val, 1;
is $db->q("SELECT count(*) FROM tmp_vndbid WHERE v > 'ff1' AND v < 'ff100'")->val, 98;

# Yes, the ^= operator can use an index too!
like join("\n", $db->q("EXPLAIN SELECT count(*) FROM tmp_vndbid WHERE v ^= 'ff'")->flat->@*), qr/tmp_vndbid_v/;
is $db->q("SELECT count(*) FROM tmp_vndbid WHERE v ^= 'ff'")->val, 1000;

# But not in this context
unlike join("\n", $db->q("EXPLAIN SELECT count(*) FROM tmp_vndbtag WHERE 'fff123' ^= v")->flat->@*), qr/tmp_vndbtag_v/;
is $db->q("SELECT count(*) FROM tmp_vndbtag WHERE 'fff123' ^= v")->val, 10;

done_testing;
