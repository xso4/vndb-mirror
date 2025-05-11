package VNWeb::AdvSearch;

# This module comes with query definitions and helper functions to handle
# advanced search queries. Usage is as follows:
#
# my $q = fu->query(f => { advsearch => 'v' });
#
# $q->sql_where;  # Returns an SQL condition for use in a where clause.
# $q->widget_;    # Instantiate a HTML widget.


use v5.36;
use experimental 'builtin';
use builtin 'created_as_number';
use POSIX 'strftime';
use List::Util 'max';
use FU;
use FU::XMLWriter ':html5_';
use VNWeb::Auth;
use VNWeb::DB;
use VNWeb::Validation;
use VNWeb::HTML ();
use VNDB::Types;
use VNDB::ExtLinks ();
use Exporter 'import';
our @EXPORT = qw/advsearch_default/;



# Search queries should be seen as some kind of low-level assembly for
# generating complex queries, they're designed to be simple to implement,
# powerful, extendable and stable. They're also a pain to work with, but that
# comes with the trade-off.
#
# A search query can be expressed in three different representations.
#
# Normalized JSON form:
#
#   $Query      = $Combinator || $Predicate
#   $Combinator = [ 'and'||'or', $Query, .. ]
#   $Predicate  = [ $Field, $Op, $Value ]
#   $Op         = '=', '!=', '>=', '>', '<=', '<'
#   $Field      = $string
#   $Value      = $Query || $field_specific_json_value
#
#   This representation is used internally and can be exposed as an API.
#   Eventually.
#
#   Example:
#
#     [ 'and'
#     , [ 'or'    # No support for array values, so IN() queries need explicit ORs.
#       , [ 'lang', '=', 'en' ]
#       , [ 'lang', '=', 'de' ]
#       , [ 'lang', '=', 'fr' ]
#       ]
#     , [ 'olang', '!=', 'ja' ]
#     , [ 'release', '=', [ 'and' # VN has a release that matches the given query
#         , [ 'released', '>=', '2020-01-01' ]
#         , [ 'developer', '=', 'p30' ]
#         ]
#       ]
#     ]
#
# Compact JSON form:
#
#   $Query      = $Combinator || $Predicate
#   $Combinator = [ 0||1, $Query, .. ]
#   $Predicate  = [ $Field, $Op, $Value ]
#   $Op         = '=', '!=', '>=', '>', '<=', '<'
#   $Field      = $integer
#   $Tuple      = [ $integer, $integer ]
#   $Value      = $integer || $string || $Query || $Tuple
#
#   Compact JSON form uses integers to represent field names and 'and'/'or'.
#   The field numbers are specific to the query type (e.g. visual novel and
#   release queries). The accepted forms of $Value are much more limited and
#   conversion of values between compact and normalized form is
#   field-dependent.
#
#   This representation is used as an intermediate format between the
#   normalized JSON form and the compact encoded form. Conversion between
#   normalized JSON and compact JSON form requires knowledge about all fields
#   and their accepted values, while conversion between compact JSON form and
#   compact encoded form can be done mechanically. This is the reason why JS
#   works with the compact JSON form.
#
#   Same example:
#
#     [ 0
#     , [ 1
#       , [ 2, '=', 'de' ]
#       , [ 2, '=', 'en' ]
#       , [ 2, '=', 'fr' ]
#       ]
#     , [ 3, '!=', 'ja' ]
#     , [ 50, '=', [ 0
#         , [ 7, '>=', 20200101 ]
#         , [ 6, '=', 30 ]
#         ]
#       ]
#     ]
#
# Compact encoded form:
#
#   Alternative and more compact representation of the compact JSON form.
#   Intended for use in a URL query string, used characters: [0-9a-zA-Z_-]
#   (plus any unicode characters that may be present in string fields).
#   Not intended to be easy to parse or work with, optimized for short length.
#
#   Same example: 03132gde2gen2gfr3hjaN180272_0c2vQ60u


# INTEGER ENCODING
#
#   Positive integers are encoded in such a way that the first character
#   indicates the length of the encoded integer, this allows integers to be
#   concatenated without any need for a delimiter. Low numbers are encoded
#   fully in a single character. The two-character encoding uses 10 values from
#   the first character in order to make efficient use of space. The last 5
#   values of the first character are used to indicate the length of integers
#   needing more than 2 characters to encode.
#
#   Alphabet: 0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-
#    (that's base64-url, but with different indices)
#
#   Full encoding format is as follows:
#     (# representing a character from the alphabet)
#
#    FIRST   FORMAT         MIN VALUE       MAX VALUE
#     0..M    #                     0              48    -> Direct lookup in the alphabet
#     N..W    ##                   49             688    -> 49 + ($first_character-'N')*64 + $second_character
#     X       X##                 689           4_784    -> 689 + $first_character*64 + $second_character
#     Y       Y###              4_785         266_928       etc.
#     Z       Z####           266_929      17_044_144
#     _       -#####       17_044_145   1_090_785_968
#     -       _######   1_090_785_969  69_810_262_704
#
# STRING ENCODING
#
#   Strings are encoded as-is, with the following characters escaped:
#
#      [SPACE]!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~
#
#   Escaping is done by taking the index of the character into the above list,
#   encoding that index to an integer according to the integer encoding rules
#   as described above and prefixing it with '_'. Example:
#
#     "a b-c"   -> "a_0b_dc"
#
#   The end of a string can either be indicated with a '-' character, or the
#   length of the string can be encoded in a preceding field.
#
# QUERY ENCODING
#
#   Int(n) refers to the integer encoding described above.
#   Escape(s) refers to the string encoding described above.
#
#     $Query      = $Predicate | $Combinator
#
#     $CombiType  = 'and' => 0, 'or' => 1
#     $Combinator = Int($CombiType) Int($num_queries) $Query..
#
#     $Predicate  = Int($field_number) $TypedOp $Value
#
#   Both a Predicate and a Combinator start with an encoded integer. For
#   Combinator this is 0 or 1, for Predicate this is the field number (>=2).
#   A Query must either be self-delimiting or encode its own length, so that
#   these can be directly concatenated.
#
#     $Op         = '=' => 0, '!=' => 1, '>=' => 2, '>' => 3, '<=' => 4, '<' => 5
#     $Type       = integer => 0, query => 1, string2 => 2, string3 => 3, stringn => 4, Tuple => 5
#     $TypedOp    = Int( $Type*8 + $Op )
#     $Tuple      = Int($first) Int($second)
#     $Value      = Int($integer)
#                 | Escape($string2) | Escape($string3) | Escape($stringn) '-'
#                 | $Query
#                 | $Tuple
#
#   The encoded field number of a Predicate is followed by a single encoded
#   integer that covers both the operator and the type of the value. This
#   encoding leaves room for 2 additional operators. There are 3 different
#   string types: string2 and string3 are fixed-length strings of 2 and 3
#   characters, respectively, and $stringn is an arbitrary-length string that
#   ends with the '-' character.


my @alpha = (0..9, 'a'..'z', 'A'..'Z', '_', '-');
my %alpha = map +($alpha[$_],$_), 0..$#alpha;

# Assumption: @escape has less than 49 characters.
my @escape = split //, " !\"#\$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
my %escape = map +($escape[$_],$alpha[$_]), 0..$#escape;
my $escape_re = qr{([${\quotemeta join '', @escape}])};

my @ops = qw/= != >= > <= </;
my %ops = map +($ops[$_],$_), 0..$#ops;

sub _unescape_str { $_[0] =~ s{_(.)}{ $escape[$alpha{$1} // return] // return }reg }
sub _escape_str { $_[0] =~ s/$escape_re/_$escape{$1}/rg }

# Read a '-'-delimited string.
sub _dec_str {
    my($s, $i) = @_;
    my $start = $$i;
    $$i >= length $s and return while substr($s, $$i++, 1) ne '-';
    _unescape_str substr $s, $start, $$i-$start-1;
}

sub _substr { $_[1]+$_[2] <= length $_[0] ? substr $_[0], $_[1], $_[2] : undef }

sub _dec_int {
    my($s, $i) = @_;
    my $c1 = ($alpha{_substr($s, $$i++, 1) // return} // return);
    return $c1 if $c1 < 49;
    my $n = ($alpha{_substr($s, $$i++, 1) // return} // return);
    return 49 + ($c1-49)*64 + $n if $c1 < 59;
    $n = $n*64 + ($alpha{_substr($s, $$i++, 1) // return} // return) for (1..$c1-59+1);
    $n + (689, 4785, 266929, 17044145, 1090785969)[$c1-59]
}

sub _dec_query {
    my($s, $i) = @_;
    my $c1 = _dec_int($s, $i) // return;
    my $c2 = _dec_int($s, $i) // return;
    return [ $c1, map +(_dec_query($s, $i) // return), 1..$c2 ] if $c1 <= 1;
    my($op, $type) = ($c2 % 8, int ($c2 / 8));
    [ $c1, $ops[$op],
        $type == 0 ? (_dec_int($s, $i) // return) :
        $type == 1 ? (_dec_query($s, $i) // return) :
        $type == 2 ? do { my $v = _unescape_str(_substr($s, $$i, 2) // return) // return; $$i += 2; $v } :
        $type == 3 ? do { my $v = _unescape_str(_substr($s, $$i, 3) // return) // return; $$i += 3; $v } :
        $type == 4 ? (_dec_str($s, $i) // return) :
        $type == 5 ? [ _dec_int($s, $i) // return, _dec_int($s, $i) // return ] : undef ]
}

sub _enc_int {
    my($n) = @_;
    return if $n < 0;
    return $alpha[$n] if $n < 49;
    return $alpha[49 + int(($n-49)/64)] . $alpha[($n-49)%64] if $n < 689;
    sub r { ($_[0] > 1 ? r($_[0]-1,int $_[1]/64) : '').$alpha[$_[1]%64] }
    return 'X'.r 2, $n -        689 if $n <        4785;
    return 'Y'.r 3, $n -       4785 if $n <      266929;
    return 'Z'.r 4, $n -     266929 if $n <    17044145;
    return '_'.r 5, $n -   17044145 if $n <  1090785969;
    return '-'.r 6, $n - 1090785969 if $n < 69810262705;
}

sub _is_tuple  { ref $_[0] eq 'ARRAY' && $_[0]->@* == 2 && (local $_ = $_[0][1]) =~ /^[0-9]+$/ }

# Assumes that the query is already in compact JSON form.
sub _enc_query {
    my($q) = @_;
    return ($alpha[$q->[0]])._enc_int($#$q).join '', map _enc_query($_), @$q[1..$#$q] if $q->[0] <= 1;
    my sub r { _enc_int($q->[0])._enc_int($ops{$q->[1]} + 8*$_[0]) }
    return r(5)._enc_int($q->[2][0])._enc_int($q->[2][1]) if _is_tuple $q->[2];
    return r(1)._enc_query($q->[2]) if ref $q->[2];
    if(created_as_number($q->[2])) {
        my $s = _enc_int $q->[2];
        return r(0).$s if defined $s;
    }
    my $esc = _escape_str $q->[2];
    return r(2).$esc if length $esc == 2;
    return r(3).$esc if length $esc == 3;
    r(4).$esc.'-';
}




# Define a $Field, args:
#   $type      -> 'v', 'c', etc.
#   $name      -> $Field name, must be stable and unique for the $type.
#   $num       -> Numeric identifier for compact encoding, must be >= 2 and same requirements as $name.
#                 Fields that don't occur often should use numbers above 50, for better encoding of common fields.
#   $value     -> FU::Validate schema for value validation, or $query_type to accept a nested query.
#   %options:
#       $op      -> Operator definitions and sql() generation functions.
#       sql      -> sql() generation function that is called for all operators.
#       sql_list -> Alternative to the '=' and '!=' $op definitions to optimize lists of (in)equality queries.
#                   sql() generation function that is called with the following arguments:
#                   - negate, 1/0 - whether the entire query should be negated
#                   - all, 1/0 - whether all values must match, 1=all, 0=any
#                   - arrayref of values to compare for equality
#       sql_list_grp -> When using sql_list, a subroutine that returns a grouping identifier for the given value.
#                       Only values with the same group identifier will be given to a single sql_list call.
#                       May return to disable sql_list support for specific values.
#       compact  -> Function to convert a value from normalized JSON form into compact JSON form.
#
#   An implementation for the '!=' operator will be supplied automatically if it's not explicitely defined.
#   NOTE: That implementation does NOT work for NULL values.
our(%FIELDS, %NUMFIELDS);
sub f {
    my($t, $num, $n, $v, @opts) = @_;
    my %f = (
        num   => $num,
        value => ref $v eq 'HASH' ? FU::Validate->compile($v) : $v,
        @opts,
    );
    $f{'='}  = sub { $f{sql_list}->(0,0,[$_]) } if !$f{'='}  && $f{sql_list};
    $f{'!='} = sub { $f{sql_list}->(1,0,[$_]) } if !$f{'!='} && $f{sql_list};
    $f{'!='} = sub { sql 'NOT (', $f{'='}->(@_), ')' } if $f{'='} && !$f{'!='};
    $f{vndbid} = ref $v eq 'HASH' && $v->{vndbid} && !ref $v->{vndbid} && $v->{vndbid};
    $f{int} = ref $f{value} && ($v->{fuzzyrdate} || $f{value}{_scalartype});
    $FIELDS{$t}{$n} = \%f;
    die "Duplicate number $num for $t\n" if $NUMFIELDS{$t}{$num};
    $NUMFIELDS{$t}{$num} = $n;
}

my @TYPE; # stack of query types, $TYPE[0] is the top-level query, $TYPE[$#TYPE] the query currently being processed.


f v => 80 => 'id',        { vndbid => 'v' }, sql => sub { sql 'v.id', $_[0], \$_ };
f v => 81 => 'search',    { searchquery => 1 }, '=' => sub { $_->sql_where('v', 'v.id') };
f v =>  2 => 'lang',      { enum => \%LANGUAGE }, '=' => sub { sql 'v.c_languages && ARRAY', \$_, '::language[]' };
f v =>  3 => 'olang',     { enum => \%LANGUAGE }, '=' => sub { sql 'v.olang =', \$_ };
f v =>  4 => 'platform',  { enum => \%PLATFORM }, '=' => sub { sql 'v.c_platforms && ARRAY', \$_, '::platform[]' };
f v =>  5 => 'length',    { uint => 1, enum => \%VN_LENGTH },
    '=' => sub { sql 'COALESCE(v.c_length BETWEEN', \$VN_LENGTH{$_}{low}, 'AND', \$VN_LENGTH{$_}{high}, ', v.length =', \$_, ')' };
f v =>  7 => 'released',  { fuzzyrdate => 1 }, sql => sub { sql 'v.c_released', $_[0], \($_ == 1 ? strftime('%Y%m%d', gmtime) : $_) };
f v =>  9 => 'popularity',{ uint => 1, range => [ 0,  100] }, sql => sub { sql 'v.c_votecount', $_[0], \($_*150) }; # XXX: Deprecated
f v => 10 => 'rating',    { uint => 1, range => [10,  100] }, sql => sub { sql 'v.c_rating', $_[0], \($_*10) };
f v => 11 => 'votecount', { uint => 1, range => [ 0,1<<30] }, sql => sub { sql 'v.c_votecount', $_[0], \$_ };
f v => 61 => 'has_description', { uint => 1, range => [1,1] }, '=' => sub { 'v.description <> \'\'' };
f v => 62 => 'has_anime',       { uint => 1, range => [1,1] }, '=' => sub { 'EXISTS(SELECT 1 FROM vn_anime va WHERE va.id = v.id)' };
f v => 63 => 'has_screenshot',  { uint => 1, range => [1,1] }, '=' => sub { 'EXISTS(SELECT 1 FROM vn_screenshots vs WHERE vs.id = v.id)' };
f v => 64 => 'has_review',      { uint => 1, range => [1,1] }, '=' => sub { 'EXISTS(SELECT 1 FROM reviews r WHERE r.vid = v.id AND NOT r.c_flagged)' };
f v => 65 => 'on_list',         { uint => 1, range => [1,1] },
    '=' => sub { auth ? sql 'v.id IN(SELECT vid FROM ulist_vns WHERE uid =', \auth->uid, auth->api2Listread ? () : 'AND NOT c_private', ')' : '1=0' };
f v => 66 => 'devstatus', { uint => 1, enum => \%DEVSTATUS }, '=' => sub { 'v.devstatus =', \$_ };

f v =>  8 => 'tag',      { type => 'any', func => \&_validate_tag }, compact => \&_compact_tag, sql_list => _sql_where_tag('tags_vn_inherit');
f v => 14 => 'dtag',     { type => 'any', func => \&_validate_tag }, compact => \&_compact_tag, sql_list => _sql_where_tag('tags_vn_direct');

f v => 12 => 'label',    { type => 'any', func => \&_validate_label },
    compact => sub { [ ($_->[0] =~ s/^u//r)*1, $_->[1]*1 ] },
    sql_list => \&_sql_where_label, sql_list_grp => sub { $_->[1] == 0 ? undef : $_->[0] };

f v => 13 => 'anime_id',  { id => 1 },
    sql_list => sub {
        my($neg, $all, $val) = @_;
        sql 'v.id', $neg ? 'NOT' : '', 'IN(SELECT id FROM vn_anime WHERE aid IN', $val, $all && @$val > 1 ? ('GROUP BY id HAVING COUNT(aid) =', \scalar @$val) : (), ')';
    };

f v => 50 => 'release',  'r', '=' => sub { sql 'v.id IN(SELECT rv.vid FROM releases r JOIN releases_vn rv ON rv.id = r.id WHERE NOT r.hidden AND', $_, ')' };
f v => 51 => 'character','c', '=' => sub { sql 'v.id IN(SELECT cv.vid FROM chars c JOIN chars_vns cv ON cv.id = c.id WHERE NOT c.hidden AND', $_, ')' }; # TODO: Spoiler setting?
f v => 52 => 'staff',    's', '=' => sub {
    # The "Staff" filter includes both vn_staff and vn_seiyuu. Union those tables together and filter on that.
    sql 'v.id IN(SELECT vs.id
                   FROM (SELECT id, aid, role FROM vn_staff UNION ALL SELECT id, aid, NULL FROM vn_seiyuu) vs
                   JOIN staff_aliast s ON s.aid = vs.aid
                  WHERE NOT s.hidden AND', $_, ')' };
f v => 55 => 'developer', 'p', '=' => sub { sql 'EXISTS(SELECT 1 FROM producers p, unnest(v.c_developers) vcd(x) WHERE p.id = vcd.x AND NOT p.hidden AND', $_, ')' };

# Deprecated.
f v =>  6 => 'developer_id', { vndbid => 'p' }, '=' => sub { sql 'v.c_developers && ARRAY', \$_, '::vndbid[]' };



f r => 80 => 'id',       { vndbid => 'r' }, sql => sub { sql 'r.id', $_[0], \$_ };
f r => 81 => 'search',   { searchquery => 1 }, '=' => sub { $_->sql_where('r', 'r.id') };
f r =>  2 => 'lang',     { enum => \%LANGUAGE },
    sql_list => sub {
        my($neg, $all, $val) = @_;
        sql 'r.id', $neg ? 'NOT' : '', 'IN(SELECT id FROM releases_titles WHERE NOT mtl AND lang IN', $val, $all && @$val > 1 ? ('GROUP BY id HAVING COUNT(lang) =', \scalar @$val) : (), ')';
    };

f r =>  4 => 'platform', { default => undef, enum => \%PLATFORM },
    sql_list_grp => sub { defined $_ },
    sql_list => sub {
        my($neg, $all, $val) = @_;
        return sql $neg ? '' : 'NOT', 'EXISTS(SELECT 1 FROM releases_platforms WHERE id = r.id)' if !defined $val->[0];
        sql 'r.id', $neg ? 'NOT' : '', 'IN(SELECT id FROM releases_platforms WHERE platform IN', $val, $all && @$val > 1 ? ('GROUP BY id HAVING COUNT(platform) =', \scalar @$val) : (), ')';
    };

f r =>  7 => 'released', { fuzzyrdate => 1 }, sql => sub { sql 'r.released', $_[0], \($_ == 1 ? strftime('%Y%m%d', gmtime) : $_) };
f r =>  8 => 'resolution',        { length => 2, elems => { uint => 1, max => 32767 } },
    sql => sub { sql 'r.reso_x', $_[0], \$_->[0], 'AND r.reso_y', $_[0], \$_->[1], $_->[0] ? 'AND r.reso_x > 0' : () };
f r =>  9 => 'resolution_aspect', { length => 2, elems => { uint => 1, max => 32767 } },
    sql => sub { sql 'r.reso_x', $_[0], \$_->[0], 'AND r.reso_y', $_[0], \$_->[1], 'AND r.reso_x*100000/GREATEST(1, r.reso_y) =', \(int ($_->[0]*100000/max(1,$_->[1]))), $_->[0] ? 'AND r.reso_x > 0' : () };
f r => 10 => 'minage',   { default => undef, uint => 1, enum => \%AGE_RATING },
    sql => sub { defined $_ ? sql 'r.minage', $_[0], \$_ : $_[0] eq '=' ? 'r.minage IS NULL' : 'r.minage IS NOT NULL' };
f r => 11 => 'medium',   { default => undef, enum => \%MEDIUM },
    '=' => sub { !defined $_ ? 'NOT EXISTS(SELECT 1 FROM releases_media rm WHERE rm.id = r.id)' : sql 'EXISTS(SELECT 1 FROM releases_media rm WHERE rm.id = r.id AND rm.medium =', \$_, ')' };
f r => 12 => 'voiced',   { default => 0, uint => 1, enum => \%VOICED }, '=' => sub { sql 'r.voiced =', \$_ };
f r => 13 => 'animation_ero',   { uint => 1, enum => \%ANIMATED }, '=' => sub { sql 'NOT r.patch AND r.ani_ero =', \$_ };
f r => 14 => 'animation_story', { uint => 1, enum => \%ANIMATED }, '=' => sub { sql 'NOT r.patch AND r.ani_story =', \$_ };

my %ANIFLAGS = (
    ''     => 'IS NULL',
    'no'   => '= 0',
    'na'   => '= 1',
    'hand' => '& 4 > 0',
    'vect' => '& 8 > 0',
    '3d'   => '& 16 > 0',
    'live' => '& 32 > 0',
);
f r => 70 => 'ani_story_sp',  { default => undef, enum => \%ANIFLAGS }, '=' => sub { 'NOT r.patch AND r.ani_story_sp', $ANIFLAGS{ $_ // '' } };
f r => 71 => 'ani_story_cg',  { default => undef, enum => \%ANIFLAGS }, '=' => sub { 'NOT r.patch AND r.ani_story_cg', $ANIFLAGS{ $_ // '' } };
f r => 72 => 'ani_cutscene',  { default => undef, enum => [qw/na hand vect 3d live/] }, '=' => sub { 'NOT r.patch AND r.ani_cutscene', $ANIFLAGS{ $_ // '' } };
f r => 73 => 'ani_ero_sp',    { default => undef, enum => \%ANIFLAGS }, '=' => sub { 'NOT r.patch AND r.ani_ero_sp', $ANIFLAGS{ $_ // '' } };
f r => 74 => 'ani_ero_cg',    { default => undef, enum => \%ANIFLAGS }, '=' => sub { 'NOT r.patch AND r.ani_ero_cg', $ANIFLAGS{ $_ // '' } };
f r => 75 => 'ani_bg',        { default => undef, uint => 1, enum => [0,1] }, '=' => sub { 'NOT r.patch AND r.ani_bg', $_ ? () : defined $_ ? '= false' : 'is null' };
f r => 76 => 'ani_face',      { default => undef, uint => 1, enum => [0,1] }, '=' => sub { 'NOT r.patch AND r.ani_face', $_ ? () : defined $_ ? '= false' : 'is null' };

f r => 15 => 'engine',   { default => '' }, '=' => sub { sql 'r.engine =', \$_ };
f r => 16 => 'rtype',    { enum => \%RELEASE_TYPE }, '=' => sub { $#TYPE && $TYPE[$#TYPE-1] eq 'v' ? sql 'rv.rtype =', \$_ : sql 'r.id IN(SELECT id FROM releases_vn WHERE rtype =', \$_, ')' };
f r => 18 => 'rlist',    { uint => 1, enum => \%RLIST_STATUS }, sql_list => sub {
        my($neg, $all, $val) = @_;
        return '1=0' if !auth;
        sql 'r.id', $neg ? 'NOT' : '', 'IN(SELECT rid FROM rlists WHERE uid =', \auth->uid, 'AND status IN', $val, $all && @$val > 1 ? ('GROUP BY rid HAVING COUNT(status) =', \scalar @$val) : (), ')';
    };
f r => 19 => 'extlink',  _extlink_filter('r', 'releases_extlinks');
f r => 20 => 'drm',      { default => '' }, '=' => sub { sql 'EXISTS(SELECT 1 FROM drm JOIN releases_drm rd ON rd.drm = drm.id WHERE drm.name =', \$_, 'AND rd.id = r.id)' };
f r => 61 => 'patch',    { uint => 1, range => [1,1] }, '=' => sub { 'r.patch' };
f r => 62 => 'freeware', { uint => 1, range => [1,1] }, '=' => sub { 'r.freeware' };
f r => 64 => 'uncensored',{uint => 1, range => [1,1] }, '=' => sub { 'r.uncensored' };
f r => 65 => 'official', { uint => 1, range => [1,1] }, '=' => sub { 'r.official' };
f r => 66 => 'has_ero',  { uint => 1, range => [1,1] }, '=' => sub { 'r.has_ero' };
f r => 53 => 'vn',       'v', '=' => sub { sql 'r.id IN(SELECT rv.id FROM releases_vn rv JOIN vn v ON v.id = rv.vid WHERE NOT v.hidden AND', $_, ')' };
f r => 55 => 'producer', 'p', '=' => sub { sql 'r.id IN(SELECT rp.id FROM releases_producers rp JOIN producers p ON p.id = rp.pid WHERE NOT p.hidden AND', $_, ')' };

# Deprecated.
f r =>  6 => 'developer_id',{ vndbid => 'p' }, '=' => sub { sql 'r.id IN(SELECT id FROM releases_producers WHERE developer AND pid =', \$_, ')' }; # Does not have a new equivalent
f r => 17 => 'producer_id', { vndbid => 'p' }, '=' => sub { sql 'r.id IN(SELECT id FROM releases_producers WHERE pid =', \$_, ')' };
f r => 63 => 'doujin',      { uint => 1, range => [1,1] }, '=' => sub { 'r.doujin' };



f c => 80 => 'id',         { vndbid => 'c' }, sql => sub { sql 'c.id', $_[0], \$_ };
f c => 81 => 'search',     { searchquery => 1 }, '=' => sub { $_->sql_where('c', 'c.id') };
f c =>  2 => 'role',       { enum => \%CHAR_ROLE  }, '=' => sub { $#TYPE && $TYPE[$#TYPE-1] eq 'v' ? sql 'cv.role =', \$_ : sql 'c.id IN(SELECT id FROM chars_vns WHERE role =', \$_, ')' };
f c =>  3 => 'blood_type', { enum => \%BLOOD_TYPE }, '=' => sub { sql 'c.bloodt =', \$_ };
f c =>  4 => 'sex',        { default => '', func => sub { $_[0] = '' if $_[0] eq 'unknown'; 1 }, enum => {%CHAR_SEX, unknown => 1} }, '=' => sub { sql 'c.sex =', \$_ };
f c =>  5 => 'sex_spoil',  { default => '', func => sub { $_[0] = '' if $_[0] eq 'unknown'; 1 }, enum => {%CHAR_SEX, unknown => 1} }, '=' => sub { sql '(c.sex =', \$_, 'AND c.spoil_sex IS NULL) OR c.spoil_sex IS NOT DISTINCT FROM', \$_ };
f c => 16 => 'gender',     { default => '', func => sub { $_[0] = '' if $_[0] eq 'unknown'; 1 }, enum => {%CHAR_GENDER, unknown => 1} },
    '=' => sub { sql 'c.gender =', \$_, /^(|m|f)$/ ? ('OR (c.gender IS NULL AND c.sex =', \$_, ')') : () };
f c => 17 => 'gender_spoil',{default => '', func => sub { $_[0] = '' if $_[0] eq 'unknown'; 1 }, enum => {%CHAR_GENDER, unknown => 1} }, '=' => sub { sql_or
        sql('c.gender =', \$_, 'AND c.spoil_gender IS NULL'),
        sql('c.spoil_gender =', \$_),
        /^(|m|f)$/ ? sql('c.spoil_gender IS NULL AND c.gender IS NULL AND (c.spoil_sex =', \$_, 'OR (c.spoil_sex IS NULL AND c.sex =', \$_, '))') : (),
    };
f c =>  6 => 'height',     { default => undef, uint => 1, max => 32767 },
    sql => sub { !defined $_ ? sql 'c.height', $_[0], 0 : sql 'c.height <> 0 AND c.height', $_[0], \$_ };
f c =>  7 => 'weight',     { default => undef, uint => 1, max => 32767 },
    sql => sub { !defined $_ ? sql('c.weight IS', $_[0] eq '=' ? '' : 'NOT', 'NULL') : sql 'c.weight', $_[0], \$_ };
f c =>  8 => 'bust',       { default => undef, uint => 1, max => 32767 },
    sql => sub { !defined $_ ? sql 'c.s_bust', $_[0], 0 : sql 'c.s_bust <> 0 AND c.s_bust', $_[0], \$_ };
f c =>  9 => 'waist',      { default => undef, uint => 1, max => 32767 },
    sql => sub { !defined $_ ? sql 'c.s_waist', $_[0], 0 : sql 'c.s_waist <> 0 AND c.s_waist', $_[0], \$_ };
f c => 10 => 'hips',       { default => undef, uint => 1, max => 32767 },
    sql => sub { !defined $_ ? sql 'c.s_hip', $_[0], 0 : sql 'c.s_hip <> 0 AND c.s_hip', $_[0], \$_ };
f c => 11 => 'cup',        { default => undef, enum => \%CUP_SIZE },
    sql => sub { !defined $_ ? sql 'c.cup_size', $_[0], "''" : sql 'c.cup_size <> \'\' AND c.cup_size', $_[0], \$_ };
f c => 12 => 'age',        { default => undef, uint => 1, max => 32767 },
    sql => sub { !defined $_ ? sql('c.age IS', $_[0] eq '=' ? '' : 'NOT', 'NULL') : sql 'c.age', $_[0], \$_ };
f c => 13 => 'trait',      { type => 'any', func => \&_validate_trait }, compact => \&_compact_trait, sql_list => _sql_where_trait('traits_chars', 'cid');
f c => 15 => 'dtrait',     { type => 'any', func => \&_validate_trait }, compact => \&_compact_trait, sql_list => _sql_where_trait('chars_traits', 'id');
f c => 14 => 'birthday',   { default => [0,0], length => 2, elems => { uint => 1, max => 31 } },
    '=' => sub { $_->[1] ? sql 'c.birthday =', \($_->[0]*100 + $_->[1]) : sql 'c.birthday BETWEEN', \($_->[0]*100), 'AND', \($_->[0]*100 + 99) };

# XXX: When this field is nested inside a VN query, it may match seiyuu linked to other VNs.
# This can be trivially fixed by adding an (AND vs.id = v.id) clause, but that results in extremely slow queries that I've no clue how to optimize.
f c => 52 => 'seiyuu', 's', '=' => sub { sql 'c.id IN(SELECT vs.cid FROM vn_seiyuu vs JOIN staff_aliast s ON s.aid = vs.aid WHERE NOT s.hidden AND', $_, ')' };
f c => 53 => 'vn',     'v', '=' => sub { sql 'c.id IN(SELECT cv.id FROM chars_vns cv JOIN vn v ON v.id = cv.vid WHERE NOT v.hidden AND', $_, ')' };



# Staff filters need 'staff_aliast s', aliases are treated as separate rows.
f s =>  2 => 'lang',      { enum => \%LANGUAGE }, '=' => sub { sql 's.lang =', \$_ };
f s =>  3 => 'id',        { vndbid => 's' }, sql => sub { sql 's.id', $_[0], \$_ };
f s =>  4 => 'gender',    { default => '', func => sub { $_[0] = '' if $_[0] eq 'unknown'; 1 }, enum => {%STAFF_GENDER, unknown => 1} }, '=' => sub { sql 's.gender =', \$_ };
f s =>  5 => 'role',      { enum => [ 'seiyuu', keys %CREDIT_TYPE ] },
    sql_list_grp => sub { $_ eq 'seiyuu' ? undef : '' },
    sql_list => sub {
        my($neg, $all, $val) = @_;
        my @grp = $all && @$val > 1 ? ('GROUP BY vs.aid HAVING COUNT(vs.role) =', \scalar @$val) : ();
        if($#TYPE && $TYPE[$#TYPE-1] eq 'v') {
            # Shortcut referencing the vn_staff table we're already querying
            return $val->[0] eq 'seiyuu' ? 'vs.role IS NULL' : sql 'vs.role IN', $val if !@grp && !$neg;
            return sql $neg ? 'NOT' : '', 'EXISTS(SELECT 1 FROM vn_seiyuu vs WHERE vs.id = v.id AND vs.aid = s.aid)' if $val->[0] eq 'seiyuu';
            sql 's.aid', $neg ? 'NOT' : '', 'IN(SELECT vs.aid FROM vn_staff vs WHERE vs.id = v.id AND vs.role IN', $val, @grp, ')';
        } else {
            return sql $neg ? 'NOT' : '', 'EXISTS(SELECT 1 FROM vn_seiyuu vs JOIN vn v ON v.id = vs.id WHERE NOT v.hidden AND vs.aid = s.aid)' if $val->[0] eq 'seiyuu';
            sql 's.aid', $neg ? 'NOT' : '', 'IN(SELECT vs.aid FROM vn_staff vs JOIN vn v ON v.id = vs.id WHERE NOT v.hidden AND vs.role IN', $val, @grp, ')';
        }
    };
f s =>  6 => 'extlink',   _extlink_filter('s', 'staff_extlinks');
f s => 61 => 'ismain',    { uint => 1, range => [1,1] }, '=' => sub { 's.aid = s.main' };
f s => 80 => 'search',    { searchquery => 1 }, '=' => sub { $_->sql_where('s', 's.id', 's.aid') };
f s => 81 => 'aid',       { id => 1 }, '=' => sub { sql 's.aid =', \$_ };

f p =>  2 => 'lang',      { enum => \%LANGUAGE }, '=' => sub { sql 'p.lang =', \$_ };
f p =>  3 => 'id',        { vndbid => 'p' }, sql => sub { sql 'p.id', $_[0], \$_ };
f p =>  4 => 'type',      { enum => \%PRODUCER_TYPE }, '=' => sub { sql 'p.type =', \$_ };
f p =>  5 => 'extlink',   _extlink_filter('p', 'producers_extlinks');
f p => 80 => 'search',    { searchquery => 1 }, '=' => sub { $_->sql_where('p', 'p.id') };


f g =>  2 => 'id',        { vndbid => 'g' }, sql => sub { sql 't.id', $_[0], \$_ };
f g =>  3 => 'category',  { enum => \%TAG_CATEGORY }, '=' => sub { sql 't.cat =', \$_ };
f g => 80 => 'search',    { searchquery => 1 }, '=' => sub { $_->sql_where('g', 't.id') };


f i =>  2 => 'id',        { vndbid => 'i' }, sql => sub { sql 't.id', $_[0], \$_ };
f i => 80 => 'search',    { searchquery => 1 }, '=' => sub { $_->sql_where('i', 't.id') };


f q =>  2 => 'id',        { vndbid => 'q' }, sql => sub { sql 'q.id', $_[0], \$_ };
f q => 53 => 'vn',        'v', '=' => sub { sql 'EXISTS(SELECT 1 FROM vn v WHERE NOT v.hidden AND q.vid = v.id AND', $_, ')' };
f q => 54 => 'character', 'c', '=' => sub { sql 'EXISTS(SELECT 1 FROM chars c WHERE NOT c.hidden AND q.cid = c.id AND', $_, ')' };
f q => 81 => 'random',    { uint => 1, range => [1,1] },
    '=' => sub { sql 'q.id = (SELECT id FROM quotes WHERE rand <= (SELECT random()) ORDER BY rand DESC LIMIT 1)' };



# 'extlink' filter accepts the following values:
# - $name            - Whether the entry has a link of site $name
# - [ $name, $val ]  - Whether the entry has a link of site $name with the given $val
# - "$name,$val"     - Compact version of above (not really *compact* by any means, but this filter isn't common anyway)
# - "http://..."     - Auto-detect version of [$name,$val]
# TODO: This only handles links defined in %LINKS, but it would be nice to also support links from Wikidata & PlayAsia.
sub _extlink_filter($type, $tbl) {
    my $L = \%VNDB::ExtLinks::LINKS;
    my %links = map +($_, $L->{$_}), grep $L->{$_}{ent} =~ /$type/i, keys %$L;

    my sub _val {
        return 1 if !ref $_[0] && $links{$_[0]}; # just $name
        if(!ref $_[0] && $_[0] =~ /^https?:/) { # URL
            for (keys %links) {
                if($links{$_}{full_regex} && $_[0] =~ $links{$_}{full_regex}) {
                    $_[0] = [ $_, (grep defined, @{^CAPTURE})[0] ];
                    last;
                }
            }
            return { msg => 'Unrecognized URL format' } if !ref $_[0];
        }
        $_[0] = [ split /,/, $_[0], 2 ] if !ref $_[0]; # compact $name,$val form

        # normalized $name,$val form
        return 0 if ref $_[0] ne 'ARRAY' || $_[0]->@* != 2 || ref $_[0][0] || ref $_[0][1] || !defined $_[0][1];
        return { msg => "Unknown site '$_[0][0]'" } if !$links{$_[0][0]};
        1
    }

    my sub _sql {
        return sql "EXISTS(SELECT 1 FROM $tbl ix WHERE ix.id = $type.id AND ix.c_site =", \"$_", ')' if !ref; # just name
        sql "EXISTS(SELECT 1 FROM $tbl ix JOIN extlinks il ON il.id = ix.link AND il.site = ix.c_site WHERE ix.id = $type.id AND il.site =", \"$_->[0]", 'AND il.value =', \"$_->[1]", ')';
    }
    my sub _comp { ref $_ ? $_->[0].','.$_->[1] : $_ }
    ({ type => 'any', func => \&_val }, '=' => \&_sql, compact => \&_comp)
}


# Accepts either:
# - $tag
# - [$tag, $exclude_lies*16*3 + int($minlevel*5)*3 + $maxspoil] (compact form)
# - [$tag, $maxspoil, $minlevel]
# - [$tag, $maxspoil, $minlevel, $exclude_lies]
# Normalizes to the latter two.
sub _validate_tag {
    $_[0] = [$_[0],0,0] if ref $_[0] ne 'ARRAY'; # just a tag id
    $_[0][0] = eval { FU::Validate->compile({ vndbid => 'g' })->validate($_[0][0]) } || return 0;
    if($_[0]->@* == 2) { # compact form
        return 0 if !defined $_[0][1] || ref $_[0][1] || $_[0][1] !~ /^[0-9]+$/;
        ($_[0][1],$_[0][2],$_[0][3]) = ($_[0][1]%3, int($_[0][1]%(3*16)/3)/5, int($_[0][1]/3/16) == 1 ? 1 : 0);
    }
    # normalized form
    return 0 if $_[0]->@* < 3 || $_[0]->@* > 4;
    return 0 if !defined $_[0][1] || ref $_[0][1] || $_[0][1] !~ /^[0-2]$/;
    return 0 if !defined $_[0][2] || ref $_[0][2] || $_[0][2] !~ /^(?:[0-2](?:\.[0-9]+)?|3(?:\.0+)?)$/;
    $_[0][1] *= 1;
    $_[0][2] *= 1;
    if ($_[0]->@* == 4) {
        return 0 if !defined $_[0][3] || ref $_[0][3] || $_[0][3] !~ /^[0-1]$/;
        $_[0][3] *= 1;
        pop $_[0]->@* if !$_[0][3];
    }
    1
}

sub _compact_tag { my $id = ($_->[0] =~ s/^g//r)*1; $_->[1] == 0 && $_->[2] == 0 && !$_->[3] ? $id : [ $id, ($_->[3]?16*3:0) + int($_->[2]*5)*3 + $_->[1] ] }
sub _compact_trait { my $id = ($_->[0] =~ s/^i//r)*1; $_->[1] == 0 && !$_->[2] ? $id : [ $id, ($_->[2]?3:0) + $_->[1] ] }

# Accepts either:
# - $trait
# - [$trait, $exclude_lies*3 + $maxspoil]  (compact form)
# - [$trait, $maxspoil]
# - [$trait, $maxspoil, $exclude_lies]
# Normalizes to the latter two.
sub _validate_trait {
    $_[0] = [$_[0],0] if ref $_[0] ne 'ARRAY'; # just a trait id
    $_[0][0] = eval { FU::Validate->compile({ vndbid => 'i' })->validate($_[0][0]) } || return 0;
    return 0 if !defined $_[0][1] || ref $_[0][1] || $_[0][1] !~ /^[0-9]+$/;
    ($_[0][1], $_[0][2]) = ($_[0][1]%3, int($_[0][1]/3) == 1 ? 1 : 0) if $_[0]->@* == 2;
    return 0 if $_[0]->@* != 3;
    return 0 if $_[0][1] > 2;
    return 0 if !defined $_[0][2] || ref $_[0][2] || $_[0][2] !~ /^[01]$/;
    $_[0][1] = 2 if $_[0][1] == 0 && $_[0][2]; # Workaround for an older UI bug that incorrectly set "No spoilers, exclude lies" instead of "Max spoilers, exclude lies"
    $_[0][1] *= 1;
    $_[0][2] *= 1;
    pop $_[0]->@* if $_[0]->@* == 3 && !$_[0][2];
    1
}


# Accepts either $label or [$uid, $label]. Normalizes to the latter. $label=0 is used for 'Unlabeled'.
sub _validate_label {
    $_[0] = [fu->{advsearch_uid}||auth->uid, $_[0]] if ref $_[0] ne 'ARRAY';
    $_[0][0] = eval { FU::Validate->compile({ vndbid => 'u' })->validate($_[0][0]) } || return 0;
    $_[0]->@* == 2 && defined $_[0][1] && !ref $_[0][1] && $_[0][1] =~ /^(?:0|[1-9][0-9]{0,5})$/
}


sub _validate($t, $q, $count) {
    return { msg => 'Invalid query' } if ref $q ne 'ARRAY' || @$q < 2 || !defined $q->[0] || ref $q->[0];
    return { msg => 'Too many predicates' } if $$count++ > 1000;

    $q->[0] = $q->[0] == 0 ? 'and' : $q->[0] == 1 ? 'or'
            : $NUMFIELDS{$t}{$q->[0]} // return { msg => 'Unknown field', field => $q->[0] }
        if $q->[0] =~ /^[0-9]+$/;

    # combinator
    if($q->[0] eq 'and' || $q->[0] eq 'or') {
        for(@$q[1..$#$q]) {
            my $r = _validate($t, $_, $count);
            return $r if !$r || ref $r;
        }
        return 1;
    }

    # predicate
    return { msg => 'Invalid predicate' } if @$q != 3 || !defined $q->[1] || ref $q->[1];
    my $f = $FIELDS{$t}{$q->[0]};
    return { msg => 'Unknown field', field => $q->[0] } if !$f;
    return { msg => 'Invalid operator', field => $q->[0], op => $q->[1] } if !defined $ops{$q->[1]} || (!$f->{$q->[1]} && !$f->{sql});
    return _validate($f->{value}, $q->[2], $count) if !ref $f->{value};
    eval { $q->[2] = $f->{value}->validate($q->[2]); 1 } ||
        return { msg => 'Invalid value', field => $q->[0], value => $q->[2], error => $@ };
    1
}


sub _validate_adv {
    my $t = shift;
    return { msg => 'Invalid JSON', error => $@ =~ s{[\s\r\n]* at /[^ ]+ line.*$}{}smr } if !ref $_[0] && $_[0] =~ /^\[/ && !eval { $_[0] = FU::Util::json_parse($_[0]); 1 };
    if(!ref $_[0]) {
        my($v,$i) = ($_[0],0);
        return { msg => 'Invalid compact encoded form', character_index => $i } if !($_[0] = _dec_query($v, \$i));
        return { msg => 'Trailing garbage' } if $i != length $v;
    }
    if(ref $_[0] eq 'ARRAY' && $_[0]->@* == 0) {
        $_[0] = bless {type=>$t}, __PACKAGE__;
        return 1;
    }
    my $count = 0;
    my $v = _validate($t, $_[0], \$count);
    $_[0] = bless { type => $t, query => $_[0] }, __PACKAGE__ if $v && !ref $v;
    $v
}



# 'advsearch' validation, accepts either a compact encoded string, JSON string or an already decoded array.
$FU::Validate::default_validations{advsearch} = sub($t) {
    +{ type => 'any', default => bless({type=>$t}, __PACKAGE__), func => sub { _validate_adv $t, $_[0] } }
};

# 'advsearch_err' validation; Same as the 'advsearch' validation except it never throws an error.
# If the validation failed, this returns an empty query that will cause widget_() to display a warning message.
$FU::Validate::default_validations{advsearch_err} = sub($t) {
    +{ type => 'any', default => bless({type=>$t}, __PACKAGE__), func => sub {
        my $r = _validate_adv $t, $_[0];
        $_[0] = bless {type=>$t,error=>1}, __PACKAGE__ if !$r || ref $r eq 'HASH';
        1
    } }
};

$FU::Validate::error_format{advsearch} = sub($e) {
    ($e->{field} ? "advsearch field '$e->{field}': " : 'advsearch: ').$e->{msg}.(ref $e->{error} ? ': '.(FU::Validate::err::errors($e->{error}))[0] : '')
};


# "Canonicalize"/simplify a query (in Normalized JSON form):
# - Merges nested and/or's where possible
# - Removes duplicate filters where possible
# - Sorts fields and values, for deterministic processing
#
# This function is unaware of the behavior of individual filters, so it can't
# currently simplify a query like "(a < 10) and (a < 9)" into "a < 9".
#
# The returned query is suitable for generating SQL and comparison of different
# queries, but should not be given to the JS UI as it changes the way fields
# are merged.
sub _canon {
    my($t, $q) = @_;
    return [ $q->[0], $q->[1], _canon($_->{value}, $q->[2]) ] if (local $_ = $FIELDS{$t}{$q->[0]}) && !ref $_->{value};
    return $q if $q->[0] ne 'or' && $q->[0] ne 'and';
    my @l = map _canon($t, $_), @$q[1..$#$q];
    @l = map $_->[0] eq $q->[0] ? @$_[1..$#$_] : $_, @l; # Merge nested and/or's
    return $l[0] if @l == 1; # and/or with a single field -> flatten

    sub _stringify { ref $_[0] ? join ':', map _stringify($_//''), $_[0]->@* : $_[0] }
    my %l = map +(_stringify($_),$_), @l;
    [ $q->[0], map $l{$_}, sort keys %l ]
}


# returns an sql_list function for tags
sub _sql_where_tag {
    my($table) = @_;
    sub {
        my($neg, $all, $val) = @_;
        my %f; # spoiler -> rating -> lie -> list
        my @l;
        push $f{$_->[1]*1}{$_->[2]*1}{$_->[3]?1:''}->@*, $_->[0] for @$val;
        for my $s (keys %f) {
            for my $r (keys $f{$s}->%*) {
                for my $l (keys $f{$s}{$r}->%*) {
                    push @l, sql_and
                        $s < 2 ? sql('spoiler <=', \$s) : (),
                        $r > 0 ? sql('rating >=', \$r) : (),
                        $l ? ('NOT lie') : (),
                        sql('tag IN', $f{$s}{$r}{$l});
                }
            }
        }
        sql 'v.id', $neg ? 'NOT' : (), 'IN(SELECT vid FROM', $table, 'WHERE', sql_or(@l), $all && @$val > 1 ? ('GROUP BY vid HAVING COUNT(tag) =', \scalar @$val) : (), ')'
    }
}

sub _sql_where_trait {
    my($table, $cid) = @_;
    sub {
        my($neg, $all, $val) = @_;
        my %f; # spoiler -> list
        my @l;
        push $f{$_->[1]*1}{$_->[2]?1:''}->@*, $_->[0] for @$val;
        for my $s (keys %f) {
            for my $l (keys $f{$s}->%*) {
                push @l, sql_and
                    $s < 2 ? sql('spoil <=', \$s) : (),
                    $l ? ('NOT lie') : (),
                    sql('tid IN', $f{$s}{$l});
            }
        }
        sql 'c.id', $neg ? 'NOT' : (), 'IN(SELECT', $cid, 'FROM', $table, 'WHERE', sql_or(@l), $all && @$val > 1 ? ('GROUP BY', $cid, 'HAVING COUNT(tid) =', \scalar @$val) : (), ')'
    }
}


# Assumption: All labels in a group are for the same uid and label==0 has its own group.
sub _sql_where_label {
    my($neg, $all, $val) = @_;
    my $uid = $val->[0][0];
    require VNWeb::ULists::Lib;
    my $own = VNWeb::ULists::Lib::ulists_priv($uid);
    my @lbl = map $_->[1], @$val;

    # Unlabeled
    if($lbl[0] == 0) {
        return '1=0' if !$own;
        return sql $neg ? 'NOT' : (), 'EXISTS(SELECT 1 FROM ulist_vns WHERE vid = v.id AND uid =', \$uid, "AND labels IN('{}','{7}'))";
    }

    if(!$own) {
        # Label 7 can always be queried, do a lookup for the rest.
        fu->{lblvis}{$uid} ||= { 7, 1, map +($_->{id},1), fu->dbAlli('SELECT id FROM ulist_labels WHERE NOT private AND uid =', \$uid)->@* };
        my $vis = fu->{lblvis}{$uid};
        return $neg ? '1=1' : '1=0' if $all && grep !$vis->{$_}, @lbl; # AND query but one label is private -> no match
        @lbl = grep $vis->{$_}, @lbl;
        return $neg ? '1=1' : '1=0' if !@lbl; # All requested labels are private -> no match
    }

    sql 'v.id', $neg ? 'NOT' : (), 'IN(
        SELECT vid
          FROM ulist_vns
         WHERE uid =', \$uid,
          'AND labels', $all ? '@>' : '&&', sql_array(@lbl), '::smallint[]',
               $own ? () : 'AND NOT c_private',
    ')'
}


sub _sql_where {
    my($t, $q) = @_;

    if($q->[0] eq 'and' || $q->[0] eq 'or') {
        my %f; # For sql_list; field -> op -> group -> list of values
        my @l; # Remaining non-batched queries
        for my $cq (@$q[1..$#$q]) {
            my $cf = $FIELDS{$t}{$cq->[0]};
            my $grp = !$cf || !$cf->{sql_list} || ($cq->[1] ne '=' && $cq->[1] ne '!=') ? undef
                : !$cf->{sql_list_grp} ? ''
                : do { local $_ = $cq->[2]; $cf->{sql_list_grp}->($_) };
            if(defined $grp) {
                push $f{$cq->[0]}{$cq->[1]}{$grp}->@*, $cq->[2];
            } else {
                push @l, _sql_where($t, $cq);
            }
        }

        for my $field (keys %f) {
            for my $op (keys $f{$field}->%*) {
                push @l, $FIELDS{$t}{$field}{sql_list}->(
                    $q->[0] eq 'and' ? ($op eq '=' ? (0, 1) : (1, 0)) : $op eq '=' ? (0, 0) : (1, 1),
                    $_
                ) for values $f{$field}{$op}->%*;
            }
        }

        return sql '(', ($q->[0] eq 'and' ? sql_and @l : sql_or @l), ')';
    }

    my $f = $FIELDS{$t}{$q->[0]};
    my $func = $f->{$q->[1]} || $f->{sql};
    local $_ = ref $f->{value} ? $q->[2] : do {
        push @TYPE, $f->{value};
        my $v = _sql_where($f->{value}, $q->[2]);
        pop @TYPE;
        $v;
    };
    sql '(', $func->($q->[1]), ')';
}


sub sql_where {
    my($self) = @_;
    @TYPE = ($self->{type});
    $self->{query} ? _sql_where $self->{type}, _canon $self->{type}, $self->{query} : '1=1';
}


sub json { shift->{query} }


sub _compact_json {
    my($t, $q) = @_;
    return [ $q->[0] eq 'and' ? 0 : 1, map _compact_json($t, $_), @$q[1..$#$q] ] if $q->[0] eq 'and' || $q->[0] eq 'or';

    my $f = $FIELDS{$t}{$q->[0]};
    [ int $f->{num}, $q->[1],
          $f->{compact}       ? do { local $_ = $q->[2]; $f->{compact}->($_) }
        : !defined $q->[2]    ? ''
        : _is_tuple( $q->[2]) ? [ int($q->[2][0] =~ s/^[a-z]//rg), int($q->[2][1]) ]
        : $f->{vndbid}        ? int ($q->[2] =~ s/^$f->{vndbid}//rg)
        : $f->{int}           ? int $q->[2]
        : ref $f->{value}     ? "$q->[2]" : _compact_json($f->{value}, $q->[2])
    ]
}


sub compact_json {
    my($self) = @_;
    $self->{compact} //= $self->{query} && _compact_json($self->{type}, $self->{query});
    $self->{compact};
}


sub _extract_ids {
    my($t,$q,$ids) = @_;
    if($q->[0] eq 'and' || $q->[0] eq 'or') {
        _extract_ids($t, $_, $ids) for @$q[1..$#$q];
    } else {
        my $f = $FIELDS{$t}{$q->[0]};
        $ids->{$q->[2]} = 1 if $f->{vndbid};
        $ids->{"anime$q->[2]"} = 1 if $q->[0] eq 'anime_id';
        $ids->{$q->[2][0]} = 1 if $q->[0] ne 'extlink' && ref $f->{value} && ref $q->[2] eq 'ARRAY'; # Ugly heuristic, may have false positives
        _extract_ids($f->{value}, $q->[2], $ids) if !ref $f->{value};
    }
}


sub widget_ {
    my($self, $count, $time) = @_;

    # TODO: labels can be lazily loaded to reduce page weight
    fu->{js_labels} = 1;

    my %ids;
    _extract_ids($self->{type}, $self->{query}, \%ids) if $self->{query};

    my %o = (
        spoilers  => auth->pref('spoilers')||0,
                     # TODO: Can also be lazily loaded.
        saved     => auth ? fu->dbAlli('SELECT name AS id, query FROM saved_queries WHERE uid =', \auth->uid, ' AND qtype =', \$self->{type}, 'ORDER BY name') : [],
        uid       => auth->uid,
        qtype     => $self->{type},
        query     => $self->compact_json(),
        producers => [ map +{id => $_}, grep /^p/, keys %ids ],
        staff     => [ map +{id => $_}, grep /^s/, keys %ids ],
        tags      => [ map +{id => $_}, grep /^g/, keys %ids ],
        traits    => [ map +{id => $_}, grep /^i/, keys %ids ],
        anime     => [ map +{id => $_=~s/^anime//rg}, grep /^anime/, keys %ids ],
    );

    enrich_merge id => sql('SELECT id, title[1+1] AS name FROM', VNWeb::TitlePrefs::producerst(), 'p WHERE id IN'), $o{producers};
    enrich_merge id => sql('SELECT id, id AS sid, title[1+1] FROM', VNWeb::TitlePrefs::staff_aliast(), 's WHERE aid = main AND id IN'), $o{staff};
    enrich_merge id => 'SELECT id, name FROM tags WHERE id IN', $o{tags};
    enrich_merge id => 'SELECT t.id, t.name, g.name AS group_name FROM traits t LEFT JOIN traits g ON g.id = t.gid WHERE t.id IN', $o{traits};
    enrich_merge id => 'SELECT id, title_romaji FROM anime WHERE id IN', $o{anime};
    $_->{id} *= 1 for $o{anime}->@*;

    div_ class => 'xsearch', VNWeb::HTML::widget(AdvSearch => \%o), '';

    p_ class => 'center standout',
        'Error parsing search query. The URL was probably corrupted in some way. '
        .'Please report a bug if you opened this page from VNDB (as opposed to getting here from an external site).'
        if $self->{error};

    if (@_ > 1) {
        p_ class => 'center', sub {
            input_ type => 'submit', value => 'Search';
            txt_ sprintf ' %d result%s in %.3fs', $count, $count == 1 ? '' : 's', $time if defined $count;
        };
        div_ class => 'warning', sub {
            h2_ 'ERROR: Query timed out.';
            p_ q{
            This usually happens when your combination of filters is too complex for the server to handle.
            This may also happen when the server is overloaded with other work, but that's much less common.
            You can adjust your filters or try again later.
            };
        } if !defined $count;
    }
}


sub TO_QUERY($self) {
    return '' if !$self->{query};
    $self->{enc_query} //= _enc_query $self->compact_json;
}

*enc_query = \&TO_QUERY;


sub extract_searchquery {
    my($self) = @_;
    my $q = $self->{query};
    return ($self) if !$q;
    return (bless({type => $self->{type}}, __PACKAGE__), $q->[2]) if @$q == 3 && $q->[1] eq '=' && ref $q->[2] eq 'VNWeb::Validate::SearchQuery';
    if($q->[0] eq 'and') {
        my(@newq, $s);
        for (@{$q}[1..$#$q]) {
            if(@$_ == 3 && $_->[1] eq '=' && ref $_->[2] eq 'VNWeb::Validate::SearchQuery') {
                return ($self) if $s;
                $s = $_->[2];
            } else {
                push @newq, $_;
            }
        }
        return (bless({type => $self->{type}, query => ['and',@newq]}, __PACKAGE__), $s) if $s;
    }
    return ($self);
}


# Returns the saved default query for the current user, or an empty query if none has been set.
sub advsearch_default {
    my($t) = @_;
    if(auth) {
        my $def = fu->dbVali('SELECT query FROM saved_queries WHERE qtype =', \$t, 'AND name = \'\' AND uid =', \auth->uid);
        return FU::Validate->compile({ advsearch => $t })->validate($def) if $def;
    }
    bless {type=>$t}, __PACKAGE__;
}

1;
