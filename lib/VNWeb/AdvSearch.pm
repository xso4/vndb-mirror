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
use TUWF;
use VNWeb::Auth;
use VNWeb::DB;
use VNWeb::Validation;
use VNDB::Types;


# Search query (JSON):
#
#   $Query      = $Combinator || $Predicate
#   $Combinator = [ 'and'||'or'||0||1, $Query, .. ]
#   $Predicate  = [ $Field, $Op, $Value ]
#   $Op         = '=', '!=', '>=', '>', '<=', '<'
#   $Tuple      = [ $string || $integer, $integer ]
#   $Triple     = [ $string || $integer, $integer, $integer ]
#   $Value      = $integer || $string || $Query || $Tuple | $Triple
#
#   Accepted values for $Op and $Value depend on $Field.
#   $Field can be referred to by name or number, the latter is used for the
#   compact encoding.
#
#   $Tuple and $Triple are special and used by a few filters; the first value
#   may be a VNDBID or an integer, the second and third values must be plain
#   integers so that they can be differentiated from a $Query.
#
# e.g. normalized JSON form:
#
#   [ 'and'
#   , [ 'or'    # No support for array values, so IN() queries need explicit ORs.
#     , [ 'lang', '=', 'en' ]
#     , [ 'lang', '=', 'de' ]
#     , [ 'lang', '=', 'fr' ]
#     ]
#   , [ 'olang', '!=', 'ja' ]
#   , [ 'char', '=', [ 'and' # VN has a character that matches the given query
#       , [ 'bust', '>=', 40 ]
#       , [ 'bust', '<=', 100 ]
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
#     $Type       = integer => 0, query => 1, string2 => 2, string3 => 3, stringn => 4, Tuple => 5, Triple => 6
#     $TypedOp    = Int( $Type*8 + $Op )
#     $Tuple      = Int($first) Int($second)
#     $Triple     = Int($first) Int($second) Int($third)
#     $Value      = Int($integer)
#                 | Escape($string2) | Escape($string3) | Escape($stringn) '-'
#                 | $Query
#                 | $Tuple
#                 | $Triple
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
        $type == 5 ? [ _dec_int($s, $i) // return, _dec_int($s, $i) // return ] :
        $type == 6 ? [ _dec_int($s, $i) // return, _dec_int($s, $i) // return, _dec_int($s, $i) // return ] : undef ]
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
sub _is_triple { ref $_[0] eq 'ARRAY' && $_[0]->@* == 3 && (local $_ = $_[0][1]) =~ /^[0-9]+$/ }

# Assumes that the query is already in compact JSON form.
sub _enc_query {
    my($q) = @_;
    return ($alpha[$q->[0]])._enc_int($#$q).join '', map _enc_query($_), @$q[1..$#$q] if $q->[0] <= 1;
    my sub r { _enc_int($q->[0])._enc_int($ops{$q->[1]} + 8*$_[0]) }
    return r(5)._enc_int($q->[2][0])._enc_int($q->[2][1]) if _is_tuple $q->[2];
    return r(6)._enc_int($q->[2][0])._enc_int($q->[2][1])._enc_int($q->[2][2]) if _is_triple $q->[2];
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
#       $op    -> Operator definitions and sql() generation functions.
#       sql    -> sql() generation function that is called for all operators.
#
#   An implementation for the '!=' operator will be supplied automatically if it's not explicitely defined.
my(%FIELDS, %NUMFIELDS);
sub f {
    my($t, $num, $n, $v, @opts) = @_;
    my %f = (
        num   => $num,
        value => ref $v eq 'HASH' ? tuwf->compile($v) : $v,
        @opts,
    );
    $f{'!='} = sub { sql 'NOT (', $f{'='}->(@_), ')' } if $f{'='} && !$f{'!='};
    $f{vndbid} = ref $v eq 'HASH' && $v->{vndbid} && !ref $v->{vndbid} && $v->{vndbid};
    $f{int} = ref $f{value} && ($v->{fuzzyrdate} || $f{value}->analyze->{type} eq 'int' || $f{value}->analyze->{type} eq 'bool');
    $FIELDS{$t}{$n} = \%f;
    $NUMFIELDS{$t}{$num} = $n;
}


f v =>  2 => 'lang',     { enum => \%LANGUAGE }, '=' => sub { sql 'v.c_languages && ARRAY', \$_, '::language[]' };
f v =>  3 => 'olang',    { enum => \%LANGUAGE }, '=' => sub { sql 'v.c_olang     && ARRAY', \$_, '::language[]' };
f v =>  4 => 'platform', { enum => \%PLATFORM }, '=' => sub { sql 'v.c_platforms && ARRAY', \$_, '::platform[]' };
f v =>  5 => 'length',   { uint => 1, enum => \%VN_LENGTH }, '=' => sub { sql 'v.length =', \$_ };
f v =>  7 => 'released', { fuzzyrdate => 1 }, sql => sub { sql 'v.c_released', $_[0], \($_ == 1 ? strftime('%Y%m%d', gmtime) : $_) };

f v =>  6 => 'developer',{ vndbid => 'p' },
    '=' => sub { sql 'v.id IN(SELECT rv.vid FROM releases r JOIN releases_vn rv ON rv.id = r.id JOIN releases_producers rp ON rp.id = r.id
                               WHERE NOT r.hidden AND rp.pid = vndbid_num(', \$_, ') AND rp.developer)' };

f v =>  8 => 'tag',      { type => 'any', func => \&_validate_tag },
    '=' => sub { sql 'v.id IN(SELECT vid FROM tags_vn_inherit WHERE tag = vndbid_num(', \$_->[0], ') AND spoiler <=', \$_->[1], 'AND rating >=', \$_->[2], ')' };

f v => 50 => 'release',  'r', '=' => sub { sql 'v.id IN(SELECT rv.vid FROM releases r JOIN releases_vn rv ON rv.id = r.id WHERE NOT r.hidden AND', $_, ')' };


f r =>  2 => 'lang',     { enum => \%LANGUAGE }, '=' => sub { sql 'r.id IN(SELECT id FROM releases_lang WHERE lang =', \$_, ')' };
f r =>  4 => 'platform', { enum => \%PLATFORM }, '=' => sub { sql 'r.id IN(SELECT id FROM releases_platforms WHERE platform =', \$_, ')' };
f r =>  6 => 'developer',{ vndbid => 'p' }, '=' => sub { sql 'r.id IN(SELECT id FROM releases_producers WHERE developer AND pid = vndbid_num(', \$_, '))' };
f r =>  7 => 'released', { fuzzyrdate => 1 }, sql => sub { sql 'r.released', $_[0], \($_ == 1 ? strftime('%Y%m%d', gmtime) : $_) };



# XXX: Accepts either $tag or [$tag, $maxspoil, $minlevel], normalizes to the latter
sub _validate_tag {
    $_[0] = [$_[0],0,0] if ref $_[0] ne 'ARRAY';
    my $v = tuwf->compile({ vndbid => 'g' })->validate($_[0][0]);
    return 0 if $v->err;
    $_[0][0] = $v->data;
    return 0 if !defined $_[0][1] || ref $_[0][1] || $_[0][1] !~ /^[0-2]$/;
    return 0 if !defined $_[0][2] || ref $_[0][2] || $_[0][2] !~ /^[0-3]$/;
    1
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


sub _sql_where {
    my($t, $q) = @_;
    return sql_and map _sql_where($t, $_), @$q[1..$#$q] if $q->[0] eq 'and';
    return sql_or  map _sql_where($t, $_), @$q[1..$#$q] if $q->[0] eq 'or';

    my $f = $FIELDS{$t}{$q->[0]};
    my $func = $f->{$q->[1]} || $f->{sql};
    local $_ = ref $f->{value} ? $q->[2] : _sql_where($f->{value}, $q->[2]);
    $func->($q->[1]);
}


sub sql_where {
    my($self) = @_;
    $self->{query} ? _sql_where $self->{type}, $self->{query} : '1=1';
}


sub _compact_json {
    my($t, $q) = @_;
    return [ $q->[0] eq 'and' ? 0 : 1, map _compact_json($t, $_), @$q[1..$#$q] ] if $q->[0] eq 'and' || $q->[0] eq 'or';

    my $f = $FIELDS{$t}{$q->[0]};
    [ int $f->{num}, $q->[1],
          _is_tuple( $q->[2]) ? [ int($q->[2][0] =~ s/^[a-z]//rg), int($q->[2][1]) ]
        : _is_triple($q->[2]) ? [ int($q->[2][0] =~ s/^[a-z]//rg), int($q->[2][1]), int($q->[2][2]) ]
        : $f->{vndbid}       ? int ($q->[2] =~ s/^$f->{vndbid}//rg)
        : $f->{int}          ? int $q->[2]
        : ref $f->{value}    ? "$q->[2]" : _compact_json($f->{value}, $q->[2])
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
        $ids->{$q->[2][0]} = 1 if _is_tuple($q->[2]) || _is_triple($q->[2]);
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

    $o{qtype} = $self->{type};
    $o{query} = $self->compact_json;
    $o{defaultSpoil} = auth->pref('spoilers')||0;

    state $schema ||= tuwf->compile({ type => 'hash', keys => {
        qtype        => {},
        query        => { type => 'array', required => 0 },
        defaultSpoil => { uint => 1 },
        producers    => $VNWeb::Elm::apis{ProducerResult}[0],
        tags         => $VNWeb::Elm::apis{TagResult}[0],
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
