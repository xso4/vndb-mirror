package VNWeb::AdvSearch;

# This module comes with query definitions and helper functions to handle
# advanced search queries. Usage is as follows:
#
# my $q = tuwf->validate(get => f => { advsearch => 'v' })->data;
#
# $q->sql_where;  # Returns an SQL condition for use in a where clause.
# $q->elm_;       # Instantiate an Elm widget


use v5.26;
use warnings;
use B;
use POSIX 'strftime';
use List::Util 'max';
use TUWF;
use VNWeb::Auth;
use VNWeb::DB;
use VNWeb::Validation;
use VNDB::Types;


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
#   compact encoded form can be done mechanically. This is the reason why Elm
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

sub _dec_int {
    my($s, $i) = @_;
    my $c1 = ($alpha{substr $s, $$i++, 1} // return);
    return $c1 if $c1 < 49;
    my $n = ($alpha{substr $s, $$i++, 1} // return);
    return 49 + ($c1-49)*64 + $n if $c1 < 59;
    $n = $n*64 + ($alpha{substr $s, $$i++, 1} // return) for (1..$c1-59+1);
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
        $type == 2 ? do { my $v = _unescape_str(substr $s, $$i, 2) // return; $$i += 2; $v } :
        $type == 3 ? do { my $v = _unescape_str(substr $s, $$i, 3) // return; $$i += 3; $v } :
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
    if(!(B::svref_2object(\$q->[2])->FLAGS & B::SVp_POK)) {
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
#   $value     -> TUWF::Validate schema for value validation, or $query_type to accept a nested query.
#   %options:
#       $op      -> Operator definitions and sql() generation functions.
#       sql      -> sql() generation function that is called for all operators.
#       sql_list -> Alternative to the '=' and '!=' $op definitions to optimize lists of (in)equality queries.
#                   sql() generation function that is called with the following arguments:
#                   - negate, 1/0 - whether the entire query should be negated
#                   - all, 1/0 - whether all values must match, 1=all, 0=any
#                   - arrayref of values to compare for equality
#       compact  -> Function to convert a value from normalized JSON form into compact JSON form.
#
#   An implementation for the '!=' operator will be supplied automatically if it's not explicitely defined.
#   NOTE: That implementation does NOT work for NULL values.
my(%FIELDS, %NUMFIELDS);
sub f {
    my($t, $num, $n, $v, @opts) = @_;
    my %f = (
        num   => $num,
        value => ref $v eq 'HASH' ? tuwf->compile($v) : $v,
        @opts,
    );
    $f{'='}  = sub { $f{sql_list}->(0,0,[$_]) } if !$f{'='}  && $f{sql_list};
    $f{'!='} = sub { $f{sql_list}->(1,0,[$_]) } if !$f{'!='} && $f{sql_list};
    $f{'!='} = sub { sql 'NOT (', $f{'='}->(@_), ')' } if $f{'='} && !$f{'!='};
    $f{vndbid} = ref $v eq 'HASH' && $v->{vndbid} && !ref $v->{vndbid} && $v->{vndbid};
    $f{int} = ref $f{value} && ($v->{fuzzyrdate} || $f{value}->analyze->{type} eq 'int' || $f{value}->analyze->{type} eq 'bool');
    $FIELDS{$t}{$n} = \%f;
    $NUMFIELDS{$t}{$num} = $n;
}



f v =>  2 => 'lang',      { enum => \%LANGUAGE }, '=' => sub { sql 'v.c_languages && ARRAY', \$_, '::language[]' };
f v =>  3 => 'olang',     { enum => \%LANGUAGE }, '=' => sub { sql 'v.c_olang     && ARRAY', \$_, '::language[]' };
f v =>  4 => 'platform',  { enum => \%PLATFORM }, '=' => sub { sql 'v.c_platforms && ARRAY', \$_, '::platform[]' };
f v =>  5 => 'length',    { uint => 1, enum => \%VN_LENGTH }, '=' => sub { sql 'v.length =', \$_ };
f v =>  7 => 'released',  { fuzzyrdate => 1 }, sql => sub { sql 'v.c_released', $_[0], \($_ == 1 ? strftime('%Y%m%d', gmtime) : $_) };
f v =>  9 => 'popularity',{ uint => 1, range => [ 0,  100] }, sql => sub { sql 'v.c_popularity', $_[0], \($_/100) };
f v => 10 => 'rating',    { uint => 1, range => [10,  100] }, sql => sub { sql 'v.c_rating <> 0 AND v.c_rating', $_[0], \$_ };
f v => 11 => 'vote-count',{ uint => 1, range => [ 0,1<<30] }, sql => sub { sql 'v.c_votecount', $_[0], \$_ };
f v => 61 => 'has-description', { uint => 1, range => [1,1] }, '=' => sub { 'v."desc" <> \'\'' };
f v => 62 => 'has-anime',       { uint => 1, range => [1,1] }, '=' => sub { 'EXISTS(SELECT 1 FROM vn_anime va WHERE va.id = v.id)' };
f v => 63 => 'has-screenshot',  { uint => 1, range => [1,1] }, '=' => sub { 'EXISTS(SELECT 1 FROM vn_screenshots vs WHERE vs.id = v.id)' };
f v => 64 => 'has-review',      { uint => 1, range => [1,1] }, '=' => sub { 'EXISTS(SELECT 1 FROM reviews r WHERE r.vid = v.id AND NOT r.c_flagged)' };

f v =>  6 => 'developer',{ vndbid => 'p' },
    '=' => sub { sql 'v.id IN(SELECT rv.vid FROM releases r JOIN releases_vn rv ON rv.id = r.id JOIN releases_producers rp ON rp.id = r.id
                               WHERE NOT r.hidden AND rp.pid = vndbid_num(', \$_, ') AND rp.developer)' };

f v =>  8 => 'tag',      { type => 'any', func => \&_validate_tag },
    compact => sub { my $id = ($_->[0] =~ s/^g//r)*1; $_->[1] == 0 && $_->[2] == 0 ? $id : [ $id, int($_->[2]*5)*3 + $_->[1] ] },
    sql_list => \&_sql_where_tag;

f v => 50 => 'release',  'r', '=' => sub { sql 'v.id IN(SELECT rv.vid FROM releases r JOIN releases_vn rv ON rv.id = r.id WHERE NOT r.hidden AND', $_, ')' };
f v => 51 => 'character','c', '=' => sub { sql 'v.id IN(SELECT cv.vid FROM chars c JOIN chars_vns cv ON cv.id = c.id WHERE NOT c.hidden AND', $_, ')' }; # TODO: Spoiler setting?



f r =>  2 => 'lang',     { enum => \%LANGUAGE },
    sql_list => sub {
        my($neg, $all, $val) = @_;
        sql 'r.id', $neg ? 'NOT' : '', 'IN(SELECT id FROM releases_lang WHERE lang IN', $val, $all && @$val > 1 ? ('GROUP BY id HAVING COUNT(lang) =', \scalar @$val) : (), ')';
    };

f r =>  4 => 'platform', { enum => \%PLATFORM },
    sql_list => sub {
        my($neg, $all, $val) = @_;
        sql 'r.id', $neg ? 'NOT' : '', 'IN(SELECT id FROM releases_platforms WHERE platform IN', $val, $all && @$val > 1 ? ('GROUP BY id HAVING COUNT(platform) =', \scalar @$val) : (), ')';
    };

f r =>  6 => 'developer',{ vndbid => 'p' }, '=' => sub { sql 'r.id IN(SELECT id FROM releases_producers WHERE developer AND pid = vndbid_num(', \$_, '))' };
f r =>  7 => 'released', { fuzzyrdate => 1 }, sql => sub { sql 'r.released', $_[0], \($_ == 1 ? strftime('%Y%m%d', gmtime) : $_) };
f r =>  8 => 'resolution',        { type => 'array', length => 2, values => { uint => 1, max => 32767 } },
    sql => sub { sql 'NOT r.patch AND r.reso_x', $_[0], \$_->[0], 'AND r.reso_y', $_[0], \$_->[1], $_->[0] ? 'AND r.reso_x > 0' : () };
f r =>  9 => 'resolution-aspect', { type => 'array', length => 2, values => { uint => 1, max => 32767 } },
    sql => sub { sql 'NOT r.patch AND r.reso_x', $_[0], \$_->[0], 'AND r.reso_y', $_[0], \$_->[1], 'AND r.reso_x*1000/GREATEST(1, r.reso_y) =', \(int ($_->[0]*1000/max(1,$_->[1]))), $_->[0] ? 'AND r.reso_x > 0' : () };
f r => 10 => 'minage',   { required => 0, default => undef, uint => 1, enum => \%AGE_RATING },
    sql => sub { !defined $_ ? sql 'r.minage', $_[0], -1 : sql 'r.minage <> -1 AND r.minage', $_[0], \$_ };
f r => 11 => 'medium',   { required => 0, default => undef, enum => \%MEDIUM },
    '=' => sub { !defined $_ ? 'NOT EXISTS(SELECT 1 FROM releases_media rm WHERE rm.id = r.id)' : sql 'EXISTS(SELECT 1 FROM releases_media rm WHERE rm.id = r.id AND rm.medium =', \$_, ')' };
f r => 12 => 'voiced',   { uint => 1, enum => \%VOICED }, '=' => sub { sql 'NOT r.patch AND r.voiced =', \$_ };
f r => 13 => 'animation-ero',   { uint => 1, enum => \%ANIMATED }, '=' => sub { sql 'NOT r.patch AND r.ani_ero =', \$_ };
f r => 14 => 'animation-story', { uint => 1, enum => \%ANIMATED }, '=' => sub { sql 'NOT r.patch AND r.ani_story =', \$_ };
f r => 15 => 'engine',   { required => 0, default => '' }, '=' => sub { sql 'r.engine =', \$_ };
f r => 16 => 'rtype',    { enum => \%RELEASE_TYPE }, '=' => sub { sql 'r.type =', \$_ };
f r => 61 => 'patch',    { uint => 1, range => [1,1] }, '=' => sub { 'r.patch' };
f r => 62 => 'freeware', { uint => 1, range => [1,1] }, '=' => sub { 'r.freeware' };
f r => 63 => 'doujin',   { uint => 1, range => [1,1] }, '=' => sub { 'r.doujin' };
f r => 64 => 'uncensored',{uint => 1, range => [1,1] }, '=' => sub { 'r.uncensored' };
f r => 65 => 'official', { uint => 1, range => [1,1] }, '=' => sub { 'r.official' };



f c =>  2 => 'role',       { enum => \%CHAR_ROLE  }, '=' => sub { sql 'cv.role =', \$_ }; # TODO: SQL is different when not used as a subquery in VN search
f c =>  3 => 'blood-type', { enum => \%BLOOD_TYPE }, '=' => sub { sql 'c.bloodt =', \$_ };
f c =>  4 => 'sex',        { enum => \%GENDER },     '=' => sub { sql 'c.gender =', \$_ };
f c =>  5 => 'sex-spoil',  { enum => \%GENDER },     '=' => sub { sql '(c.gender =', \$_, 'AND c.spoil_gender IS NULL) OR c.spoil_gender IS NOT DISTINCT FROM', \$_ };
f c =>  6 => 'height',     { required => 0, default => undef, uint => 1, max => 32767 },
    sql => sub { !defined $_ ? sql 'c.height', $_[0], 0 : sql 'c.height <> 0 AND c.height', $_[0], \$_ };
f c =>  7 => 'weight',     { required => 0, default => undef, uint => 1, max => 32767 },
    sql => sub { !defined $_ ? sql('c.weight IS', $_[0] eq '=' ? '' : 'NOT', 'NULL') : sql 'c.weight', $_[0], \$_ };
f c =>  8 => 'bust',       { required => 0, default => undef, uint => 1, max => 32767 },
    sql => sub { !defined $_ ? sql 'c.s_bust', $_[0], 0 : sql 'c.s_bust <> 0 AND c.s_bust', $_[0], \$_ };
f c =>  9 => 'waist',      { required => 0, default => undef, uint => 1, max => 32767 },
    sql => sub { !defined $_ ? sql 'c.s_waist', $_[0], 0 : sql 'c.s_waist <> 0 AND c.s_waist', $_[0], \$_ };
f c => 10 => 'hips',       { required => 0, default => undef, uint => 1, max => 32767 },
    sql => sub { !defined $_ ? sql 'c.s_hip', $_[0], 0 : sql 'c.s_hip <> 0 AND c.s_hip', $_[0], \$_ };
f c => 11 => 'cup',        { required => 0, default => undef, enum => \%CUP_SIZE },
    sql => sub { !defined $_ ? sql 'c.cup_size', $_[0], "''" : sql 'c.cup_size <> \'\' AND c.cup_size', $_[0], \$_ };
f c => 12 => 'age',        { required => 0, default => undef, uint => 1, max => 32767 },
    sql => sub { !defined $_ ? sql('c.age IS', $_[0] eq '=' ? '' : 'NOT', 'NULL') : sql 'c.age', $_[0], \$_ };
f c => 13 => 'trait',      { type => 'any', func => \&_validate_trait },
    compact => sub { my $id = ($_->[0] =~ s/^i//r)*1; $_->[1] == 0 ? $id : [ $id, int $_->[1] ] },
    sql_list => \&_sql_where_trait;




# Accepts either $tag or [$tag, int($minlevel*5)*3+$maxspoil] (for compact form) or [$tag, $maxspoil, $minlevel]. Normalizes to the latter.
sub _validate_tag {
    $_[0] = [$_[0],0,0] if ref $_[0] ne 'ARRAY'; # just a tag id
    my $v = tuwf->compile({ vndbid => 'g' })->validate($_[0][0]);
    return 0 if $v->err;
    $_[0][0] = $v->data;
    if($_[0]->@* == 2) { # compact form
        return 0 if !defined $_[0][1] || ref $_[0][1] || $_[0][1] !~ /^[0-9]+$/;
        ($_[0][1],$_[0][2]) = ($_[0][1]%3, int($_[0][1]/3)/5);
    }
    # normalized form
    return 0 if $_[0]->@* != 3;
    return 0 if !defined $_[0][1] || ref $_[0][1] || $_[0][1] !~ /^[0-2]$/;
    return 0 if !defined $_[0][2] || ref $_[0][2] || $_[0][2] !~ /^(?:[0-2](?:\.[0-9]+)?|3(?:\.0+)?)$/;
    1
}


# Accepts either $trait or [$trait, $maxspoil]. Normalizes to the latter.
sub _validate_trait {
    $_[0] = [$_[0],0] if ref $_[0] ne 'ARRAY'; # just a trait id
    my $v = tuwf->compile({ vndbid => 'i' })->validate($_[0][0]);
    return 0 if $v->err;
    $_[0][0] = $v->data;
    $_[0]->@* == 2 && defined $_[0][1] && !ref $_[0][1] && $_[0][1] =~ /^[0-2]$/
}


sub _validate {
    my($t, $q) = @_;
    return { msg => 'Invalid query' } if ref $q ne 'ARRAY' || @$q < 2 || !defined $q->[0] || ref $q->[0];

    $q->[0] = $q->[0] == 0 ? 'and' : $q->[0] == 1 ? 'or'
            : $NUMFIELDS{$t}{$q->[0]} // return { msg => 'Unknown field', field => $q->[0] }
        if $q->[0] =~ /^[0-9]+$/;

    # combinator
    if($q->[0] eq 'and' || $q->[0] eq 'or') {
        for(@$q[1..$#$q]) {
            my $r = _validate($t, $_);
            return $r if !$r || ref $r;
        }
        return 1;
    }

    # predicate
    return { msg => 'Invalid predicate' } if @$q != 3 || !defined $q->[1] || ref $q->[1];
    my $f = $FIELDS{$t}{$q->[0]};
    return { msg => 'Unknown field', field => $q->[0] } if !$f;
    return { msg => 'Invalid operator', field => $q->[0], op => $q->[1] } if !defined $ops{$q->[1]} || (!$f->{$q->[1]} && !$f->{sql});
    return _validate($f->{value}, $q->[2]) if !ref $f->{value};
    my $r = $f->{value}->validate($q->[2]);
    return { msg => 'Invalid value', field => $q->[0], value => $q->[2], error => $r->err } if $r->err;
    $q->[2] = $r->data;
    1
}


# 'advsearch' validation, accepts either a compact encoded string, JSON string or an already decoded array.
TUWF::set('custom_validations')->{advsearch} = sub { my($t) = @_; +{ required => 0, type => 'any', default => bless({type=>$t}, __PACKAGE__), func => sub {
    return { msg => 'Invalid JSON', error => $@ =~ s{[\s\r\n]* at /[^ ]+ line.*$}{}smr } if !ref $_[0] && $_[0] =~ /^\[/ && !eval { $_[0] = JSON::XS->new->decode($_[0]); 1 };
    if(!ref $_[0]) {
        my($v,$i) = ($_[0],0);
        return { msg => 'Invalid compact encoded form', character_index => $i } if !($_[0] = _dec_query($v, \$i));
        return { msg => 'Trailing garbage' } if $i != length $v;
    }
    my $v = _validate($t, @_);
    $_[0] = bless { type => $t, query => $_[0] }, __PACKAGE__ if $v;
    $v
} } };



# "Canonicalize"/simplify a query (in Normalized JSON form):
# - Merges nested and/or's where possible
# - Removes duplicate filters where possible
# - Sorts fields and values, for deterministic processing
#
# This function is unaware of the behavior of individual filters, so it can't
# currently simplify a query like "(a < 10) and (a < 9)" into "a < 9".
#
# The returned query is suitable for generating SQL and comparison of different
# queries, but should not be given to the Elm UI as it changes the way fields
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


# sql_list function for tags
sub _sql_where_tag {
    my($neg, $all, $val) = @_;
    my %f; # spoiler -> rating -> list
    my @l;
    push $f{$_->[1]}{$_->[2]}->@*, $_->[0] for @$val;
    for my $s (keys %f) {
        for my $r (keys $f{$s}->%*) {
            push @l, sql_and
                $s < 2 ? sql('spoiler <=', \$s) : (),
                $r > 0 ? sql('rating >=', \$r) : (),
                sql('tag IN', [ map s/^.//r, $f{$s}{$r}->@* ]);
        }
    }
    sql 'v.id', $neg ? 'NOT' : (), 'IN(SELECT vid FROM tags_vn_inherit WHERE', sql_or(@l), $all && @$val > 1 ? ('GROUP BY vid HAVING COUNT(tag) =', \scalar @$val) : (), ')'
}

sub _sql_where_trait {
    my($neg, $all, $val) = @_;
    my %f; # spoiler -> list
    my @l;
    push $f{$_->[1]}->@*, $_->[0] for @$val;
    for my $s (keys %f) {
        push @l, sql_and
            $s < 2 ? sql('spoil <=', \$s) : (),
            sql('tid IN', [ map s/^.//r, $f{$s}->@* ]);
    }
    sql 'c.id', $neg ? 'NOT' : (), 'IN(SELECT cid FROM traits_chars WHERE', sql_or(@l), $all && @$val > 1 ? ('GROUP BY cid HAVING COUNT(tid) =', \scalar @$val) : (), ')'
}


sub _sql_where {
    my($t, $q) = @_;

    if($q->[0] eq 'and' || $q->[0] eq 'or') {
        my %f; # For sql_list; field -> op -> list of values
        my @l; # Remaining non-batched queries
        for my $cq (@$q[1..$#$q]) {
            my $cf = $FIELDS{$t}{$cq->[0]};
            if($cf && $cf->{sql_list} && ($cq->[1] eq '=' || $cq->[1] eq '!=')) {
                push $f{$cq->[0]}{$cq->[1]}->@*, $cq->[2];
            } else {
                push @l, _sql_where($t, $cq);
            }
        }

        for my $field (keys %f) {
            for my $op (keys $f{$field}->%*) {
                push @l, $FIELDS{$t}{$field}{sql_list}->(
                    $q->[0] eq 'and' ? ($op eq '=' ? (0, 1) : (1, 0)) : $op eq '=' ? (0, 0) : (1, 1),
                    $f{$field}{$op}
                )
            }
        }

        return $q->[0] eq 'and' ? sql_and @l : sql_or @l;
    }

    my $f = $FIELDS{$t}{$q->[0]};
    my $func = $f->{$q->[1]} || $f->{sql};
    local $_ = ref $f->{value} ? $q->[2] : _sql_where($f->{value}, $q->[2]);
    $func->($q->[1]);
}


sub sql_where {
    my($self) = @_;
    $self->{query} ? _sql_where $self->{type}, _canon $self->{type}, $self->{query} : '1=1';
}


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
        $ids->{$q->[2][0]} = 1 if ref $f->{value} && ref $q->[2] eq 'ARRAY'; # Ugly heuristic, may have false positives
        _extract_ids($f->{value}, $q->[2], $ids) if !ref $f->{value};
    }
}


sub elm_ {
    my($self) = @_;

    my(%o,%ids);
    _extract_ids($self->{type}, $self->{query}, \%ids) if $self->{query};

    $o{producers} = [ map +{id => $_=~s/^p//rg}, grep /^p/, keys %ids ];
    enrich_merge id => 'SELECT id, name, original, hidden FROM producers WHERE id IN', $o{producers};

    $o{tags} = [ map +{id => $_=~s/^g//rg}, grep /^g/, keys %ids ];
    enrich_merge id => 'SELECT id, name, searchable, applicable, state FROM tags WHERE id IN', $o{tags};

    $o{traits} = [ map +{id => $_=~s/^i//rg}, grep /^i/, keys %ids ];
    enrich_merge id => 'SELECT t.id, t.name, t.searchable, t.applicable, t.defaultspoil, t.state, g.id AS group_id, g.name AS group_name
                          FROM traits t LEFT JOIN traits g ON g.id = t.group WHERE t.id IN', $o{traits};

    $o{qtype} = $self->{type};
    $o{query} = $self->compact_json;
    $o{defaultSpoil} = auth->pref('spoilers')||0;

    state $schema ||= tuwf->compile({ type => 'hash', keys => {
        qtype        => {},
        query        => { type => 'array', required => 0 },
        defaultSpoil => { uint => 1 },
        producers    => $VNWeb::Elm::apis{ProducerResult}[0],
        tags         => $VNWeb::Elm::apis{TagResult}[0],
        traits       => $VNWeb::Elm::apis{TraitResult}[0],
    }});
    VNWeb::HTML::elm_ 'AdvSearch.Main', $schema, \%o;
}


sub query_encode {
    my($self) = @_;
    return if !$self->{query};
    $self->{query_encode} //= _enc_query $self->compact_json;
    $self->{query_encode};
}

1;
