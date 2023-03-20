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
#       # SQL column in the users table to store the saved default
#       _pref => 'tableopts_something',
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
#           sort_num => 0/1,       # Whether this is a numeric field, used in the UI to display "1→9" instead of "A→Z".
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
#   my $sql = sql('.... ORDER BY', $opts->sql_order);
#
#   $opts->view;     # Current view, 'rows', 'cards' or 'grid'
#   $opts->results;  # How many results to display
#   $opts->vis('popularity'); # is the column visible?
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
use VNWeb::Auth;
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
        sort_ids  => [], # identifier => column config hash
        col_order => [], # column config hashes in the order listed in the config
        columns   => {}, # column name => config hash
        views     => [], # supported views, as numbers
        default   => 0,  # default settings, integer form
    );
    my @vis;
    while(@_) {
        my($k,$v) = (shift,shift);
        if($k eq '_views') {
            $o{views} = [ map $views{$_}//croak("unknown view: $_"), ref $v ? @$v : $v ];
            next;
        }
        if($k eq '_pref') {
            $o{pref} = $v;
            next;
        }
        $o{columns}{$k} = $v;
        $v->{id} = $k;
        push $o{col_order}->@*, $v;
        if(defined $v->{sort_id}) {
            die "Duplicate sort_id $v->{sort_id}\n" if $o{sort_ids}[$v->{sort_id}];
            $o{sort_ids}[$v->{sort_id}] = $v;
        }
        die "Duplicate vis_id $v->{vis_id}\n" if defined $v->{vis_id} && $vis[$v->{vis_id}]++;
        $o{default} |= ($v->{sort_id} << 6) | ({qw|asc 0 desc 32|}->{$v->{sort_default}}//croak("unknown sort_default: $v->{sort_default}")) if $v->{sort_default};
        $o{default} |= 1 << ($v->{vis_id} + 12) if $v->{vis_default};
    }
    $o{views} ||= [0];
    $o{default} |= $o{views}[0];
    #warn "=== ".($o{pref}||'undef')."\n"; dump_ids(\%o);
    \%o
}


# COMPAT: For old URLs, we assume that this validation is used on the 's'
# parameter, so we can accept two formats:
# - "s=$compat_sort_column/$order"
# - "s=$compat_sort_column&o=$order"
# In the latter case, the validation will use reqGet() to get the 'o'
# parameter.
TUWF::set('custom_validations')->{tableopts} = sub {
    my($t) = @_;
    +{ onerror => sub {
        my $d = $t->{pref} && auth ? tuwf->dbVali('SELECT', $t->{pref}, 'FROM users_prefs WHERE id =', \auth->uid) : undef;
        my $o = bless([$d // $t->{default},$t], __PACKAGE__);
        $o->fixup;
    }, func => sub {
        my $obj = bless [undef, $t], __PACKAGE__;
        my($val,$ord) = $_[0] =~ m{^([^/]+)/([ad])$} ? ($1,$2) : ($_[0],undef);
        my $col = [grep $_->{compat} && $_->{compat} eq $val, values $t->{columns}->%*]->[0];
        if($col && defined $col->{sort_id}) {
            $obj->[0] = $t->{default};
            $obj->set_sort_col_id($col->{sort_id});
            $ord //= tuwf->reqGet('o');
            $obj->set_order($ord && $ord eq 'd' ? 1 : 0);
        } else {
            $obj->[0] = _dec($_[0]) // return 0;
        }
        $_[0] = $obj->fixup;
        # We could do strict validation on the individual fields, but the methods below can handle incorrect data.
        1;
    } }
};

sub fixup {
    my($obj) = @_;
    # Reset sort_col and order to their default if the current sort_col id does not exist.
    if(!$obj->[1]{sort_ids}[ $obj->sort_col_id ]) {
        $obj->set_sort_col_id(sort_col_id([$obj->[1]{default}]));
        $obj->set_order(order([$obj->[1]{default}]));
    }
    $obj
}

sub query_encode { _enc $_[0][0] }

sub view  { $views[$_[0][0] & 3] || $views[$_[0][1]{views}[0]] }
sub rows  { shift->view eq 'rows'  }
sub cards { shift->view eq 'cards' }
sub grid  { shift->view eq 'grid'  }

sub results { $results[($_[0][0] >> 2) & 7] || $results[0] }

sub order { $_[0][0] & 32 }
sub set_order { if($_[1]) { $_[0][0] |= 32 } else { $_[0][0] &= ~32 } }

sub sort_col_id { ($_[0][0] >> 6) & 63 }
sub set_sort_col_id { $_[0][0] = ($_[0][0] & (~1 - 0b111111000000)) | ($_[1] << 6) }

# Given the key of a column, returns whether it is currently sorted on ('' / 'a' / 'd')
sub sorted {
    my($self, $key) = @_;
    $self->[1]{columns}{$key}{sort_id} != $self->sort_col_id ? '' : $self->order ? 'd' : 'a';
}

# Given the key of a column and the desired order ('a'/'d'), returns a new object with that sorting applied.
sub sort_param {
    my($self, $key, $o) = @_;
    my $n = bless [@$self], __PACKAGE__;
    $n->set_order($o eq 'a' ? 0 : 1);
    $n->set_sort_col_id($self->[1]{columns}{$key}{sort_id});
    $n
}

# Returns an SQL expression suitable for use in an ORDER BY clause.
sub sql_order {
    my($self) = @_;
    my($v,$o) = $self->@*;
    my $col = $o->{sort_ids}[ $self->sort_col_id ];
    die "No column to sort on" if !$col;
    my $order = $self->order ? 'DESC' : 'ASC';
    my $opposite_order = $self->order ? 'ASC' : 'DESC';
    my $sql = $col->{sort_sql};
    $sql =~ /[?!]o/ ? ($sql =~ s/\?o/$order/rg =~ s/!o/$opposite_order/rg) : "$sql $order";
}


# Returns whether the given column key is visible.
sub vis { my $c = $_[0][1]{columns}{$_[1]}; $c && defined $c->{vis_id} && ($_[0][0] & (1 << (12+$c->{vis_id}))) }

# Given a list of column names, return a new object with only these columns visible
sub vis_param {
    my($self, @cols) = @_;
    my $n = bless [@$self], __PACKAGE__;
    $n->[0] = $n->[0] & 0b1111_1111_1111;
    $n->[0] |= 1 << (12+$self->[1]{columns}{$_}{vis_id}) for @cols;
    $n;
}


my $FORM_OUT = form_compile any => {
    save    => { required => 0 },
    views   => { type => 'array', values => { uint => 1 } },
    default => { uint => 1 },
    value   => { uint => 1 },
    sorts   => { aoh => { id => { uint => 1 }, name => {}, num => { anybool => 1 } } },
    vis     => { aoh => { id => { uint => 1 }, name => {} } },
};

elm_api TableOptsSave => $FORM_OUT, {
    save => { enum => ['tableopts_c', 'tableopts_v', 'tableopts_vt'] },
    value => { required => 0, uint => 1 }
}, sub {
    my($f) = @_;
    return elm_Unauth if !auth;
    tuwf->dbExeci('UPDATE users_prefs SET', { $f->{save} => $f->{value} }, 'WHERE id =', \auth->uid);
    elm_Success
};

sub elm_ {
    my $self = shift;
    my($v,$o) = $self->@*;
    VNWeb::HTML::elm_ TableOpts => $FORM_OUT, {
        save    => auth ? $o->{pref} : undef,
        views   => $o->{views},
        default => $o->{default},
        value   => $v,
        sorts   => [ map +{ id => $_->{sort_id}, name => $_->{name}, num => $_->{sort_num}||0 }, grep defined $_->{sort_id}, values $o->{col_order}->@* ],
        vis     => [ map +{ id => $_->{vis_id}, name => $_->{name} }, grep defined $_->{vis_id}, values $o->{col_order}->@* ],
    }, sub {
        TUWF::XML::div_ @_, sub {
            TUWF::XML::input_ type => 'hidden', name => 's', value => $self->query_encode if defined $self->query_encode
        }
    };
}


# Helpful debugging function, dumps a quick overview of assigned numeric
# identifiers for the given opts.
sub dump_ids {
    my($o) = @_;
    warn sprintf "sort %2d  %s  %s\n", $_->{sort_id}, $_->{id}, $_->{name}
        for sort { $a->{sort_id} <=> $b->{sort_id} }
            grep defined $_->{sort_id}, values $o->{col_order}->@*;
    warn sprintf "vis %2d  %s  %s\n", $_->{vis_id}, $_->{id}, $_->{name}
        for sort { $a->{vis_id} <=> $b->{vis_id} }
            grep defined $_->{vis_id}, values $o->{col_order}->@*;
}

1;
