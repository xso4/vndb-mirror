package VNWeb::Validation;

use v5.26;
use TUWF 'uri_escape';
use PWLookup;
use VNDB::Types;
use VNDB::Config;
use VNWeb::Auth;
use VNWeb::DB;
use VNDB::Func 'gtintype';
use Time::Local 'timegm';
use Carp 'croak';
use Exporter 'import';

our @EXPORT = qw/
    is_insecurepass
    form_compile
    form_changed
    validate_dbid
    can_edit
    viewget viewset
/;


TUWF::set custom_validations => {
    id          => { uint => 1, max => (1<<26)-1 },
    # 'vndbid' SQL type, accepts an arrayref with accepted prefixes.
    # If only one prefix is supported, it will also take integers and normalizes them into the formatted form.
    vndbid      => sub {
        my $multi = ref $_[0];
        my $types = $multi ? join '|', $_[0]->@* : $_[0];
        my $re = qr/^(?:$types)[1-9][0-9]{0,6}$/;
        +{ func => sub { $_[0] = "${types}$_[0]" if !$multi && $_[0] =~ /^[1-9][0-9]{0,6}$/; return $_[0] =~ $re } }
    },
    editsum     => { required => 1, length => [ 2, 5000 ] },
    page        => { uint => 1, min => 1, max => 1000, required => 0, default => 1, onerror => 1 },
    upage       => { uint => 1, min => 1, required => 0, default => 1, onerror => 1 }, # pagination without a maximum
    username    => { regex => qr/^(?!-*[a-z][0-9]+-*$)[a-z0-9-]*$/, minlength => 2, maxlength => 15 },
    password    => { length => [ 4, 500 ] },
    language    => { enum => \%LANGUAGE },
    gtin        => { required => 0, default => 0, func => sub { $_[0] = 0 if !length $_[0]; $_[0] eq 0 || gtintype($_[0]) } },
    rdate       => { uint => 1, func => \&_validate_rdate },
    fuzzyrdate  => { func => \&_validate_fuzzyrdate },
    # A tri-state bool, returns undef if not present or empty, normalizes to 0/1 otherwise
    undefbool   => { required => 0, default => undef, func => sub { $_[0] = $_[0] ? 1 : 0; 1 } },
    # An array that may be either missing (returns undef), a single scalar (returns single-element array) or a proper array
    undefarray  => sub { +{ required => 0, default => undef, type => 'array', scalar => 1, values => $_[0] } },
    # Accepts a user-entered vote string (or '-' or empty) and converts that into a DB vote number (or undef) - opposite of fmtvote()
    vnvote      => { required => 0, default => undef, regex => qr/^(?:|-|[1-9]|10|[1-9]\.[0-9]|10\.0)$/, func => sub { $_[0] = $_[0] eq '-' ? undef : 10*$_[0]; 1 } },
    # Sort an array by the listed hash keys, using string comparison on each key
    sort_keys   => sub {
        my @keys = ref $_[0] eq 'ARRAY' ? @{$_[0]} : $_[0];
        +{ type => 'array', sort => sub {
            for(@keys) {
                my $c = defined($_[0]{$_}) cmp defined($_[1]{$_}) || (defined($_[0]{$_}) && $_[0]{$_} cmp $_[1]{$_});
                return $c if $c;
            }
            0
        } }
    },
    # Sorted and unique array-of-hashes (default order is sort_keys on the sorted keys...)
    aoh         => sub { +{ type => 'array', unique => 1, sort_keys => [sort keys %{$_[0]}], values => { type => 'hash', keys => $_[0] } } },
};

sub _validate_rdate {
    return 0 if $_[0] ne 0 && $_[0] !~ /^([0-9]{4})([0-9]{2})([0-9]{2})$/;
    my($y, $m, $d) = $_[0] eq 0 ? (0,0,0) : ($1, $2, $3);

    # Re-normalize
    ($m, $d) = (0, 0) if $y == 0;
    $m = 99 if $y == 9999;
    $d = 99 if $m == 99;
    $_[0] = $y*10000 + $m*100 + $d;

    return 0 if $y && $y != 9999 && ($y < 1980 || $y > 2100);
    return 0 if $y && $m != 99 && (!$m || $m > 12);
    return 0 if $y && $d != 99 && !eval { timegm(0, 0, 0, $d, $m-1, $y) };
    return 1;
}


sub _validate_fuzzyrdate {
    $_[0] = 0 if $_[0] =~ /^unknown$/;
    $_[0] = 1 if $_[0] =~ /^today$/;
    $_[0] = 99999999 if $_[0] =~ /^tba$/;
    return 1 if $_[0] eq 1;
    VNWeb::Validation::_validate_rdate($_[0]);
}


sub is_insecurepass {
    config->{password_db} && PWLookup::lookup(config->{password_db}, shift)
}


# Recursively remove keys from hashes that have a '_when' key that doesn't
# match $when. This is a quick and dirty way to create multiple validation
# schemas from a single schema. For example:
#
#   {
#       title => { _when => 'input' },
#       name  => { },
#   }
#
# If $when is 'input', then this function returns:
#   { title => {}, name => {} }
# Otherwise, it returns:
#   { name => {} }
sub _stripwhen {
    my($when, $o) = @_;
    return $o if ref $o ne 'HASH';
    +{ map $_ eq '_when' || (ref $o->{$_} eq 'HASH' && defined $o->{$_}{_when} && $o->{$_}{_when} !~ $when) ? () : ($_, _stripwhen($when, $o->{$_})), keys %$o }
}


# Short-hand to compile a validation schema for a form. Usage:
#
#   form_compile $when, {
#       title => { _when => 'input' },
#       name  => { },
#       ..
#   };
sub form_compile {
    tuwf->compile({ type => 'hash', keys => _stripwhen @_ });
}


sub _eq_deep {
    my($a, $b) = @_;
    return 0 if ref $a ne ref $b;
    return 0 if defined $a != defined $b;
    return 1 if !defined $a;
    return 1 if !ref $a && $a eq $b;
    return 1 if ref $a eq 'ARRAY' && (@$a == @$b && !grep !_eq_deep($a->[$_], $b->[$_]), 0..$#$a);
    return 1 if ref $a eq 'HASH' && _eq_deep([sort keys %$a], [sort keys %$b]) && !grep !_eq_deep($a->{$_}, $b->{$_}), keys %$a;
    0
}


# Usage: form_changed $schema, $a, $b
# Returns 1 if there is a difference between the data ($a) and the form input
# ($b), using the normalization defined in $schema. The $schema must validate.
sub form_changed {
    my($schema, $a, $b) = @_;
    my sub norm {
        my $v = $schema->validate($_[0]);
        if($v->err) {
            require Data::Dumper;
            my $e = Data::Dumper->new([$v->err])->Terse(1)->Pair(':')->Indent(0)->Sortkeys(1)->Dump;
            my $j = JSON::XS->new->pretty->encode($_[0]);
            warn "form_changed() input did not validate according to the schema.\nError: $e\nInput: $j";
        }
        $v->unsafe_data;
    }
    !_eq_deep norm($a), norm($b);
}


# Validate identifiers against an SQL query. The query must end with a 'id IN'
# clause, where the @ids array is appended. The query must return exactly 1
# column, the id of each entry. This function throws an error if an id is
# missing from the query. For example, to test for non-hidden VNs:
#
#   validate_dbid 'SELECT id FROM vn WHERE NOT hidden AND id IN', 2,3,5,7,...;
#
# If any of those ids is hidden or not in the database, an error is thrown.
sub validate_dbid {
    my($sql, @ids) = @_;
    return if !@ids;
    $sql = ref $sql eq 'CODE' ? do { local $_ = \@ids; sql $sql->(\@ids) } : sql $sql, \@ids;
    my %dbids = map +((values %$_)[0],1), @{ tuwf->dbAlli($sql) };
    my @missing = grep !$dbids{$_}, @ids;
    croak "Invalid database IDs: ".join(',', @missing) if @missing;
}


# Returns whether the current user can edit the given database entry.
#
# Supported types:
#
#   u:
#     Requires 'id' field, can only test for editing.
#
#   t:
#     If no 'id' field, checks if the user can create a new thread
#       (permission to post in specific boards is not handled here).
#     If no 'num' field, checks if the user can reply to the existing thread.
#       Requires the 'locked' field.
#       Assumes the user is permitted to see the thread in the first place, i.e. neither hidden nor private.
#     Otherwise, checks if the user can edit the post.
#       Requires the 'user_id', 'date' and 'hidden' fields.
#
#   w:
#     If no 'id' field, checks if the user can submit a new review.
#     Otherwise, checks if the user can edit the review.
#       Requires the 'uid' field.
#
#   g/i:
#     If no 'id' field, checks if the user can create a new tag/trait.
#     Otherwise, checks if the user can edit the entry.
#
#   'dbentry_type's:
#     If no 'id' field, checks whether the user can create a new entry.
#     Otherwise, requires 'entry_hidden' and 'entry_locked' fields.
#
sub can_edit {
    my($type, $entry) = @_;

    return auth->permUsermod || auth->permDbmod || auth->permImgmod || auth->permBoardmod || auth->permTagmod || (auth && $entry->{id} == auth->uid) if $type eq 'u';
    return auth->permDbmod if $type eq 'd';

    if($type eq 't') {
        return 0 if !auth->permBoard;
        return 1 if auth->permBoardmod;
        if(!$entry->{id}) {
            # Allow at most 5 new threads per day per user.
            return auth && tuwf->dbVali('SELECT count(*) < ', \5, 'FROM threads_posts WHERE num = 1 AND date > NOW()-\'1 day\'::interval AND uid =', \auth->uid);
        } elsif(!$entry->{num}) {
            die "Can't do authorization test when 'locked' field isn't present" if !exists $entry->{locked};
            return !$entry->{locked};
        } else {
            die "Can't do authorization test when hidden/date/user_id fields aren't present"
                if !exists $entry->{hidden} || !exists $entry->{date} || !exists $entry->{user_id};
            return auth && $entry->{user_id} == auth->uid && !$entry->{hidden} && $entry->{date} > time-config->{board_edit_time};
        }
    }

    if($type eq 'w') {
        return 1 if auth->permBoardmod;
        return auth->permReview if !$entry->{id};
        return auth && auth->uid == $entry->{user_id};
    }

    if($type eq 'g' || $type eq 'i') {
        return auth && (auth->permTagmod || !$entry->{id});
    }

    die "Can't do authorization test when entry_hidden/entry_locked fields aren't present"
        if $entry->{id} && (!exists $entry->{entry_hidden} || !exists $entry->{entry_locked});

    auth->permDbmod || (auth->permEdit && !($entry->{entry_hidden} || $entry->{entry_locked}));
}


# Some user preferences can be overruled with a ?view= query parameter,
# viewget() can be used to fetch these parameters, viewset() to generate a
# query parameter with certain preferences overruled.
#
# The query parameter has the following format:
#   view=1   -> spoilers=1, traits_sexual=<default>
#   view=2s  -> spoilers=2, traits_sexual=1
#   view=2S  -> spoilers=2, traits_sexual=0
#   view=S   -> spoilers=<default>, traits_sexual=0
# i.e. a list of single-character flags:
#   0-2 -> spoilers
#   s/S -> 1/0 traits_sexual
#   n/N -> 1/0 show_nsfw
# Missing flags will use default.
#
# The parameter also contains a CSRF token to prevent direct links to pages
# with sensitive content. The token is domain-separated from the form CSRF
# tokens, but is otherwise generic for all pages and options, so if someone's
# token leaks, it's possible to generate links to any sensitive page for that
# particular user for several hours.
sub viewget {
    tuwf->req->{view} ||= do {
        my($view, $token) = tuwf->reqGet('view') =~ /^([^-]*)-(.+)$/;

        # Abort this request and redirect if the token is invalid.
        if(length($view) && (!tuwf->samesite || !length($token) || !auth->csrfcheck($token, 'view'))) {
            my $qs = join '&', map { my $k=$_; my @l=tuwf->reqGets($k); map uri_escape($k).'='.uri_escape($_), @l } grep $_ ne 'view', tuwf->reqGets();
            tuwf->resInit;
            tuwf->resRedirect(tuwf->reqPath().($qs?"?$qs":''), 'temp');
            tuwf->done;
        }

        my($sp, $ts, $ns) = $view =~ /^([0-2])?([sS]?)([nN]?)$/;
        {
            spoilers      => $sp // auth->pref('spoilers') || 0,
            traits_sexual => !$ts ? auth->pref('traits_sexual') : $ts eq 's',
            show_nsfw     => !$ns ? (auth->pref('max_sexual')||0)==2 && (auth->pref('max_violence')||0)>0 : $ns eq 'n',
        }
    };
    tuwf->req->{view}
}


# Creates a new 'view=' string with the given parameters. All other fields remain at their default.
sub viewset {
    my %s = @_;
    join '',
        $s{spoilers}//'',
        !defined $s{traits_sexual} ? '' : $s{traits_sexual} ? 's' : 'S',
        !defined $s{show_nsfw}     ? '' : $s{show_nsfw}     ? 'n' : 'N',
        '-'.auth->csrftoken(0, 'view');
}

1;
