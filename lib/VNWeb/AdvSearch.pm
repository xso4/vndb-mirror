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
#
# TODO: Compact search query encoding for in URLs. Passing around JSON is... ugly.


# Define a $Field, args:
#   $type      -> 'v', 'c', etc.
#   $name      -> $Field name
#   $value     -> TUWF::Validate schema for value validation, or $query_type to accept a nested query.
#   $op=>$sql  -> Operator definitions and sql() generation functions.
#
#   An implementation for the '!=' operator will be supplied automatically if it's not explicitely defined.
my %fields;
sub f {
    my($t, $n, $v, %op) = @_;
    my %f = (
        value => ref $v eq 'HASH' ? tuwf->compile($v) : $v,
        op    => \%op,
    );
    $f{op}{'!='} = sub { sql 'NOT (', $f{op}{'='}->(@_), ')' } if $f{op}{'='} && !$f{op}{'!='};
    $f{int} = $f{value} && ($f{value}->analyze->{type} eq 'int' || $f{value}->analyze->{type} eq 'bool');
    $fields{$t}{$n} = \%f;
}

f 'v', 'lang',  { enum => \%LANGUAGE }, '=' => sub { sql 'v.c_languages && ARRAY', \$_, '::language[]' };
f 'v', 'olang', { enum => \%LANGUAGE }, '=' => sub { sql 'v.c_olang     && ARRAY', \$_, '::language[]' };
f 'v', 'plat',  { enum => \%PLATFORM }, '=' => sub { sql 'v.c_platforms && ARRAY', \$_, '::platform[]' };



sub validate {
    my($t, $q) = @_;
    return { msg => 'Invalid query' } if ref $q ne 'ARRAY' || @$q < 2 || !defined $q->[0] || ref $q->[0];

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
    my $f = $fields{$t}{$q->[0]};
    return { msg => 'Unknown field', field => $q->[0] } if !$f;
    return { msg => 'Invalid operator', field => $q->[0], op => $q->[1] } if !$f->{op}{$q->[1]};
    return validate($f->{value}, $q->[2]) if !ref $f->{value};
    my $r = $f->{value}->validate($q->[2]);
    return { msg => 'Invalid value', field => $q->[0], value => $q->[2], error => $r->err } if $r->err;
    $q->[2] = $r->data;
    1
}


# 'advsearch' validation, accepts either a JSON representation or an already decoded array.
TUWF::set('custom_validations')->{advsearch} = sub { my($t) = @_; +{ required => 0, type => 'any', func => sub {
    return { msg => 'Invalid JSON', error => $@ =~ s{[\s\r\n]* at /[^ ]+ line.*$}{}smr } if !ref $_[0] && !eval { $_[0] = JSON::XS->new->decode($_[0]); 1 };
    validate($t, @_)
} } };


sub as_tosql {
    my($t, $q) = @_;
    return sql_and map as_tosql($t, $_), @$q[1..$#$q] if $q->[0] eq 'and';
    return sql_or  map as_tosql($t, $_), @$q[1..$#$q] if $q->[0] eq 'or';

    my $f = $fields{$t}{$q->[0]};
    local $_ = ref $f->{value} ? $q->[2] : as_tosql($f->{value}, $q->[2]);
    $f->{op}{$q->[1]}->();
}


sub coerce_for_json {
    my($t, $q) = @_;
    if($q->[0] eq 'and' || $q->[0] eq 'or') {
        coerce_for_json($t, $_) for @$q[1..$#$q];
    } else {
        my $f = $fields{$t}{$q->[0]};
        ()= $f->{int} ? $q->[2]*1 : ref $f->{value} ? "$q->[2]" : coerce_for_json($t, $q->[2]);
    }
    $q
}

sub as_elm_ {
    my($t, $q) = @_;
    elm_ 'AdvSearch.Main', 'raw', $q && coerce_for_json($t, $q);
}

1;
