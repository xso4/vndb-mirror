package VNWeb::AdvSearch;

use v5.26;
use warnings;
use TUWF;
use Exporter 'import';
use VNWeb::DB;
use VNWeb::Validation;
use VNWeb::HTML;
use VNDB::Types;

our @EXPORT = qw/ as_tosql as_elm_ /;


# Search query (JSON):
#
#   $Query      = $Combinator || $Predicate
#   $Combinator = [ 'and'||'or', $Query, .. ]
#   $Predicate  = [ $Field, $Op, $Value ]
#   $Op         = '=', '!=', '>=', '<='
#   $Value      = $integer || $string || $Query
#
#   Accepted values for $Op and $Value depend on $Field.
#   $Field can be referred to by name or number, the latter is used for the
#   compact encoding.
#
# e.g.
#
#   [ 'and'
#   , [ 'or'    # No support for array values, so IN() queries need explicit ORs.
#     , [ '=', 'lang', 'en' ]
#     , [ '=', 'lang', 'de' ]
#     , [ '=', 'lang', 'fr' ]
#     ]
#   , [ '!=', 'olang', 'ja' ]
#   , [ '=', 'char', [ 'and' # VN has a char that matches the given query
#       , [ '>=', 'bust', 40 ]
#       , [ '<=', 'bust', 100 ]
#       ]
#     ]
#   ]
#
# Search queries should be seen as some kind of low-level assembly for
# generating complex queries, they're designed to be simple to implement,
# powerful, extendable and stable. They're also a pain to work with, but that
# comes with the trade-off.


# Compact search query encoding:
#
#   Intended for use in a URL query string, used characters: [0-9a-zA-Z_-]
#   (plus any unicode characters that may be present in string fields).
#   Not intended to be easy to parse or work with, optimized for short length.
#
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
#   Strings are not self-delimiting, so their length must be encoded
#   separately (though '-' does not occur in encoded strings, so that could be
#   used as delimiter in the future).
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
#     $Op         = '=' => 0, '!=' => 1, '>=' => 2, '<=' => 3
#     $Type       = integer => 0, query => 1,   n>=9 => string with length n-9
#     $TypedOp    = Int( $Type*4 + $Op )
#     $Value      = Int($integer) | Escape($string) | $Query
#
#   The encoded field number of a Predicate is followed by a single encoded
#   integer that covers both the operator and the type of the value. This
#   encoding leaves no room for additional operators, but does have room for 7
#   more types. The (escaped) length of string arguments is encoded in the
#   $Type. Type=9 is used for the empty string, Type=10 for strings of length
#   1, etc. String lengths up to 3 can be represented by a single $TypedOp
#   character.
#
# (Only a decoder is implemented for now, encoding is done in Elm)

my @alpha = (0..9, 'a'..'z', 'A'..'Z', '_', '-');
my %alpha = map +($alpha[$_],$_), 0..$#alpha;
my @escape = split //, " !\"#\$%&'()*+,-./:;<=>?@[\\]^_`{|}~";

sub dec_int {
    my($s, $i) = @_;
    my $c1 = ($alpha{substr $s, $$i++, 1} // return);
    return $c1 if $c1 < 49;
    my $n = ($alpha{substr $s, $$i++, 1} // return);
    return 49 + ($c1-49)*64 + $n if $c1 < 59;
    $n = $n*64 + ($alpha{substr $s, $$i++, 1} // return) for (1..$c1-59+1);
    $n + (689, 4785, 266929, 17044145, 1090785969)[$c1-59]
}

# Assumption: @escape has less than 49 characters.
sub unescape_str { $_[0] =~ s{_(.)}{ $escape[$alpha{$1} // return] // return }reg }

sub dec_query {
    my($s, $i) = @_;
    my $c1 = dec_int($s, $i) // return;
    my $c2 = dec_int($s, $i) // return;
    return [ $c1 ? 'or' : 'and', map +(dec_query($s, $i) // return), 1..$c2 ] if $c1 <= 1;
    my($op, $type) = ($c2 % 4, int ($c2 / 4));
    [ $c1, ('=','!=', '>=', '<=')[$op],
        $type == 0 ? (dec_int($s, $i) // return) :
        $type == 1 ? (dec_query($s, $i) // return) :
        $type >= 9 ? do { my $v = unescape_str(substr $s, $$i, $type-9) // return; $$i += $type-9; $v } : undef ];
}



# Define a $Field, args:
#   $type      -> 'v', 'c', etc.
#   $name      -> $Field name, must be stable and unique for the $type.
#   $num       -> Numeric identifier for compact encoding, must be >= 2 and same requirements as $name.
#                 Fields that don't occur often should use numbers above 50, for better encoding of common fields.
#   $value     -> TUWF::Validate schema for value validation, or $query_type to accept a nested query.
#   $op=>$sql  -> Operator definitions and sql() generation functions.
#
#   An implementation for the '!=' operator will be supplied automatically if it's not explicitely defined.
our(%FIELDS, %NUMFIELDS);
sub f {
    my($t, $num, $n, $v, %op) = @_;
    my %f = (
        num   => $num,
        value => ref $v eq 'HASH' ? tuwf->compile($v) : $v,
        op    => \%op,
    );
    $f{op}{'!='} = sub { sql 'NOT (', $f{op}{'='}->(@_), ')' } if $f{op}{'='} && !$f{op}{'!='};
    $f{vndbid} = ref $v eq 'HASH' && $v->{vndbid} && !ref $v->{vndbid} && $v->{vndbid};
    $f{int} = ref $f{value} && ($f{value}->analyze->{type} eq 'int' || $f{value}->analyze->{type} eq 'bool');
    $FIELDS{$t}{$n} = \%f;
    $NUMFIELDS{$t}{$num} = $n;
}


f v =>  2 => 'lang',     { enum => \%LANGUAGE }, '=' => sub { sql 'v.c_languages && ARRAY', \$_, '::language[]' };
f v =>  3 => 'olang',    { enum => \%LANGUAGE }, '=' => sub { sql 'v.c_olang     && ARRAY', \$_, '::language[]' };
f v =>  4 => 'platform', { enum => \%PLATFORM }, '=' => sub { sql 'v.c_platforms && ARRAY', \$_, '::platform[]' };
f v =>  5 => 'length',   { uint => 1, enum => \%VN_LENGTH }, '=' => sub { sql 'v.length =', \$_ };
f v =>  6 => 'developer',{ vndbid => 'p' }, '=' => sub {
    sql 'v.id IN(SELECT rv.vid FROM releases r JOIN releases_vn rv ON rv.id = r.id JOIN releases_producers rp ON rp.id = r.id WHERE NOT r.hidden AND rp.pid = vndbid_num(', \$_, ') AND rp.developer)' };
f v => 50 => 'release',  'r', '=' => sub { sql 'v.id IN(SELECT rv.vid FROM releases r JOIN releases_vn rv ON rv.id = r.id WHERE', $_, ')' };


f r =>  2 => 'lang',     { enum => \%LANGUAGE }, '=' => sub { sql 'r.id IN(SELECT id FROM releases_lang WHERE lang =', \$_, ')' };
f r =>  3 => 'developer',{ vndbid => 'p' }, '=' => sub { sql 'r.id IN(SELECT id FROM releases_producers WHERE developer AND pid = vndbid_num(', \$_, '))' };



sub validate {
    my($t, $q) = @_;
    return { msg => 'Invalid query' } if ref $q ne 'ARRAY' || @$q < 2 || !defined $q->[0] || ref $q->[0];

    $q->[0] = $q->[0] == 0 ? 'and' : $q->[0] == 1 ? 'or'
            : $NUMFIELDS{$t}{$q->[0]} // return { msg => 'Unknown field', field => $q->[0] }
        if $q->[0] =~ /^[0-9]+$/;

    # combinator
    if($q->[0] eq 'and' || $q->[0] eq 'or') {
        for(@$q[1..$#$q]) {
            my $r = validate($t, $_);
            return $r if !$r || ref $r;
        }
        return 1;
    }

    # predicate
    return { msg => 'Invalid predicate' } if @$q != 3 || !defined $q->[1] || ref $q->[1];
    my $f = $FIELDS{$t}{$q->[0]};
    return { msg => 'Unknown field', field => $q->[0] } if !$f;
    return { msg => 'Invalid operator', field => $q->[0], op => $q->[1] } if !$f->{op}{$q->[1]};
    return validate($f->{value}, $q->[2]) if !ref $f->{value};
    my $r = $f->{value}->validate($q->[2]);
    return { msg => 'Invalid value', field => $q->[0], value => $q->[2], error => $r->err } if $r->err;
    $q->[2] = $r->data;
    1
}


# 'advsearch' validation, accepts either a compact encoded string, JSON string or an already decoded array.
TUWF::set('custom_validations')->{advsearch} = sub { my($t) = @_; +{ required => 0, type => 'any', func => sub {
    return { msg => 'Invalid JSON', error => $@ =~ s{[\s\r\n]* at /[^ ]+ line.*$}{}smr } if !ref $_[0] && $_[0] =~ /^\[/ && !eval { $_[0] = JSON::XS->new->decode($_[0]); 1 };
    if(!ref $_[0]) {
        my($v,$i) = ($_[0],0);
        return { msg => 'Invalid compact encoded form', character_index => $i } if !($_[0] = dec_query($v, \$i));
        return { msg => 'Trailing garbage' } if $i != length $v;
    }
    validate($t, @_)
} } };


sub as_tosql {
    my($t, $q) = @_;
    return sql_and map as_tosql($t, $_), @$q[1..$#$q] if $q->[0] eq 'and';
    return sql_or  map as_tosql($t, $_), @$q[1..$#$q] if $q->[0] eq 'or';

    my $f = $FIELDS{$t}{$q->[0]};
    local $_ = ref $f->{value} ? $q->[2] : as_tosql($f->{value}, $q->[2]);
    $f->{op}{$q->[1]}->();
}


sub coerce_for_json {
    my($t, $q) = @_;
    if($q->[0] eq 'and' || $q->[0] eq 'or') {
        coerce_for_json($t, $_) for @$q[1..$#$q];
    } else {
        my $f = $FIELDS{$t}{$q->[0]};
        # VNDBIDs are represented as ints for Elm
        $q->[2] = $f->{vndbid} ? int ($q->[2] =~ s/^$f->{vndbid}//rg)
             :    $f->{int}    ? int $q->[2]
             : ref $f->{value} ? "$q->[2]" : coerce_for_json($f->{value}, $q->[2]);
    }
    $q
}


sub extract_ids {
    my($t,$q,$ids) = @_;
    if($q->[0] eq 'and' || $q->[0] eq 'or') {
        extract_ids($t, $_, $ids) for @$q[1..$#$q];
    } else {
        my $f = $FIELDS{$t}{$q->[0]};
        $ids->{$q->[2]} = 1 if $f->{vndbid};
        extract_ids($f->{value}, $q->[2], $ids) if !ref $f->{value};
    }
}


sub as_elm_ {
    my($t, $q) = @_;

    my(%o,%ids);
    extract_ids($t, $q, \%ids) if $q;
    $o{producers} = [ map +{id => $_=~s/^p//rg}, grep /^p/, keys %ids ];
    enrich_merge id => 'SELECT id, name, original, hidden FROM producers WHERE id IN', $o{producers};

    $o{qtype} = $t;
    $o{query} = $q && coerce_for_json($t, $q);

    state $schema ||= tuwf->compile({ type => 'hash', keys => {
        qtype     => {},
        query     => { type => 'array' },
        producers => $VNWeb::Elm::apis{ProducerResult}[0],
    }});
    elm_ 'AdvSearch.Main', $schema, \%o;
}

1;
