package VNWeb::TableOpts;

# This is a helper module to handle passing around various table display
# options in a single compact query parameter.
#
# Supported options:
#
#   Sort column & order
#   Number of results per page
#   View: rows, cards or grid
#   Which columns are visible
#
# Out of scope: pagination & filtering.
#
# Usage:
#
#   my $config = tableopts
#       # Which views are supported (default: all)
#       _views => [ 'rows', 'cards', 'grid' ],
#
#       # Column config.
#       # The key names are only used internally.
#       title => {
#           name     => 'Title',   # Column name, used in the configuration box.
#           compat   => 'title',   # Name of this column for compatibility with old URLs that referred to the column by name.
#           sort_id  => 0,         # This column can be sorted on, option indicates numeric identifier (must be stable)
#           sort_sql => 'v.title', # SQL to generate when sorting on this column,
#                                  # may include '?o' placeholder that will be replaced with selected ASC/DESC,
#                                  # or '!o' as placeholder for the opposite.
#                                  # If no placeholders are present, the ASC/DESC will be added automatically.
#           sort_default => 'asc', # Set to 'asc' or 'desc' if this column should be sorted on by default.
#       },
#       popularity => {
#           name     => 'Popularity',
#           sort_id  => 1,
#           sort_sql => 'v.c_popularity ?o, v.title',
#           vis_id   => 0,      # This column can be hidden/visible, option indicates numeric identifier
#           vis_default => 1,   # If this column should be visible by default
#       };
#
#   my $opts = tuwf->validate(get => s => { tableopts => $config })->data;
#
#   my $sql = sql('.... ORDER BY', $opts->sql_order);  (TODO)
#
#   $opts->view;     # Current view, 'rows', 'cards' or 'grid'
#   $opts->results;  # How many results to display
#   $opts->vis('popularity'); # is the column visible? (TODO)
#
#
#
# Table options are encoded in a base64-encoded 31 bits integer (can be
# extended, but bitwise operations in JS are quirky beyond 31 bits).
# The bit layout is as follows, 0 being the least significant bit:
#
#    0 -  1: view      0: rows, 1: cards, 2: grid (3: unused)
#    2 -  4: results   0: 50, 1: 10, 2: 25, 3: 100, 4: 200 (5-7: unused)
#         5: order     0: ascending, 1: descending
#    6 - 11: sort column, identifier used in the configuration
#   12 - 31: column visibility, identifier in the configuration is used as bit index (12+$vis_id)
#
# This supports 64 column identifiers for sorting, 19 identifiers for visibility.

use v5.26;
use Carp 'croak';
use Exporter 'import';
use TUWF;
use VNWeb::HTML ();
use VNWeb::Validation;
use VNWeb::Elm;

our @EXPORT = ('tableopts');

my @alpha = (0..9, 'a'..'z', 'A'..'Z', '_', '-');
my %alpha = map +($alpha[$_],$_), 0..$#alpha;
sub _enc { ($_[0] >= @alpha ? _enc(int $_[0]/@alpha) : '').$alpha[$_[0]%@alpha] }
sub _dec { return if length $_[0] > 6; my $n = 0; $n = $n*@alpha + ($alpha{$_}//return) for split //, $_[0]; $n }

my @views = qw|rows cards grid|;
my %views = map +($views[$_], $_), 0..$#views;

my @results = (50, 10, 25, 100, 200);
my %results = map +($results[$_], $_), 0..$#results;


# Turn config options into something more efficient to work with
sub tableopts {
    my %o = (
        sort_ids  => [], # identifier => column name
        vis_ids   => [], # identifier => column name
        col_order => [], # column names in the order listed in the config
        columns   => {}, # column name => config hash
        views     => [], # supported views, as numbers
        default   => 0,  # default settings, integer form
    );
    while(@_) {
        my($k,$v) = (shift,shift);
        if($k eq '_views') {
            $o{views} = [ map $views{$_}//croak("unknown view: $_"), ref $v ? @$v : $v ];
            next;
        }
        $o{columns}{$k} = $v;
        push $o{col_order}->@*, $k;
        $o{sort_ids}[$v->{sort_id}] = $k if defined $v->{sort_id};
        $o{vis_ids}[$v->{vis_id}] = $k if defined $v->{vis_id};
        $o{default} |= ($v->{sort_id} << 6) | ({qw|asc 0 desc 32|}->{$v->{sort_default}}//croak("unknown sort_default: $v->{sort_default}")) if $v->{sort_default};
        $o{default} |= 1 << ($v->{vis_id} + 12) if $v->{vis_default};
    }
    $o{views} ||= [0];
    $o{default} |= $o{views}[0];
    \%o
}


TUWF::set('custom_validations')->{tableopts} = sub {
    my($t) = @_;
    +{ onerror => bless([$t->{default},$t], __PACKAGE__), func => sub {
        # TODO: compatibility with the old ?s=<colname> sort parameter
        my $v = _dec $_[0] or return 0;
        # We could do strict validation on the individual fields, but the methods below can handle incorrect data.
        $_[0] = bless [$v, $t], __PACKAGE__;
        1;
    } }
};

sub query_encode {
    my($v,$o) = $_[0]->@*;
    $v == $o->{default} ? undef : _enc $v;
}

sub view  { $views[$_[0][0] & 3] || $views[$_[0][1]{views}[0]] }
sub rows  { shift->view eq 'rows'  }
sub cards { shift->view eq 'cards' }
sub grid  { shift->view eq 'grid'  }

sub results { $results[($_[0][0] >> 2) & 7] || $results[0] }


my $FORM_OUT = form_compile any => {
    views   => { type => 'array', values => { uint => 1 } },
    default => { uint => 1 },
    value   => { uint => 1 },
    # TODO: Sorting & column visibility
};

elm_api TableOptsSave => $FORM_OUT, {}, sub { ... };

sub elm_ {
    my $self = shift;
    my($v,$o) = $self->@*;
    VNWeb::HTML::elm_ TableOpts => $FORM_OUT, {
        views   => $o->{views},
        default => $o->{default},
        value   => $v,
    }, sub {
        TUWF::XML::input_ type => 'hidden', name => 's', value => $self->query_encode if defined $self->query_encode
    };
}

1;
