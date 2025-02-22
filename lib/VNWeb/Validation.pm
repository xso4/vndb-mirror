package VNWeb::Validation;

use v5.36;
use TUWF 'uri_escape';
use VNDB::Types;
use VNDB::Config;
use VNDB::ExtLinks ();
use VNWeb::Auth;
use VNWeb::DB;
use VNDB::Func 'gtintype';
use Time::Local 'timegm';
use Carp 'croak';
use Exporter 'import';

our @EXPORT = qw/
    %RE
    samesite
    is_api
    is_unique_username
    ipinfo
    form_compile
    validate_dbid
    can_edit
    viewget viewset
/;


# Regular expressions for use in path registration
my $num = qr{[1-9][0-9]{0,6}}; # Allow up to 10 mil, SQL vndbid type can't handle more than 2^26-1 (~ 67 mil).
my $rev = qr{(?:\.(?<rev>$num))};
our %RE = (
    num  => qr{(?<num>$num)},
    uid  => qr{(?<id>u$num)},
    vid  => qr{(?<id>v$num)},
    rid  => qr{(?<id>r$num)},
    sid  => qr{(?<id>s$num)},
    cid  => qr{(?<id>c$num)},
    pid  => qr{(?<id>p$num)},
    iid  => qr{(?<id>i$num)},
    did  => qr{(?<id>d$num)},
    tid  => qr{(?<id>t$num)},
    gid  => qr{(?<id>g$num)},
    wid  => qr{(?<id>w$num)},
    qid  => qr{(?<id>q$num)},
    imgid=> qr{(?<id>(?:ch|cv|sf)$num)},
    vrev => qr{(?<id>v$num)$rev?},
    rrev => qr{(?<id>r$num)$rev?},
    prev => qr{(?<id>p$num)$rev?},
    srev => qr{(?<id>s$num)$rev?},
    crev => qr{(?<id>c$num)$rev?},
    drev => qr{(?<id>d$num)$rev?},
    grev => qr{(?<id>g$num)$rev?},
    irev => qr{(?<id>i$num)$rev?},
    postid => qr{(?<id>t$num)\.(?<num>$num)},
);


TUWF::set custom_validations => {
    id          => { uint => 1, max => (1<<26)-1 },
    # 'vndbid' SQL type, accepts an arrayref with accepted prefixes.
    # If only one prefix is supported, it will also take integers and normalizes them into the formatted form.
    vndbid      => sub {
        my $multi = ref $_[0];
        my $types = $multi ? join '|', $_[0]->@* : $_[0];
        my $re = qr/^(?:$types)[1-9][0-9]{0,6}$/;
        +{ _analyze_regex => $re, func => sub { $_[0] = "${types}$_[0]" if !$multi && $_[0] =~ /^[1-9][0-9]{0,6}$/; return $_[0] =~ $re } }
    },
    sl          => { regex => qr/^[^\t\r\n]+$/ }, # "Single line", also excludes tabs because they're weird.
    editsum     => { length => [ 2, 5000 ] },
    page        => { uint => 1, min => 1, max => 1000, default => 1, onerror => 1 },
    upage       => { uint => 1, min => 1, default => 1, onerror => 1 }, # pagination without a maximum
    username    => { regex => qr/^(?!-*[a-zA-Z][0-9]+-*$)[a-zA-Z0-9-]*$/, minlength => 2, maxlength => 15 },
    password    => { length => [ 4, 500 ] },
    language    => { enum => \%LANGUAGE },
    gtin        => { default => 0, func => sub { $_[0] = 0 if !length $_[0]; $_[0] eq 0 || gtintype($_[0]) } },
    rdate       => { uint => 1, func => \&_validate_rdate },
    fuzzyrdate  => { default => 0, func => \&_validate_fuzzyrdate },
    searchquery => { onerror => bless([],'VNWeb::Validate::SearchQuery'), func => sub { $_[0] = bless([$_[0]], 'VNWeb::Validate::SearchQuery'); 1 } },
    extlinks    => \&_validate_extlinks,
    # Calendar date, limited to 1970 - 2099 for sanity.
    # TODO: Should also validate whether the day exists, currently "2022-11-31" is accepted, but that's a bug.
    caldate     => { regex => qr/^(?:19[7-9][0-9]|20[0-9][0-9])-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12][0-9]|3[01])$/ },
    # An array that may be either missing (returns undef), a single scalar (returns single-element array) or a proper array
    undefarray  => sub { +{ default => undef, type => 'array', scalar => 1, values => $_[0] } },
    # Accepts a user-entered vote string (or '-' or empty) and converts that into a DB vote number (or undef) - opposite of fmtvote()
    vnvote      => { default => undef, regex => qr/^(?:|-|[1-9]|10|[1-9]\.[0-9]|10\.0)$/, func => sub { $_[0] = $_[0] eq '-' ? undef : 10*$_[0]; 1 } },
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
    # Fields query parameter for the API, supports multiple values or comma-delimited list, returns a hash.
    fields      => sub {
        my %keys = map +($_,1), ref $_[0] eq 'ARRAY' ? @{$_[0]} : $_[0];
        +{ default => {}, type => 'array', values => {}, scalar => 1, func => sub {
            my @l = map split(/\s*,\s*/,$_), @{$_[0]};
            return 0 if grep !$keys{$_}, @l;
            $_[0] = { map +($_,1), @l };
            1;
        } }
    },
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
    $_[0] = 0 if $_[0] =~ /^unknown$/i;
    $_[0] = 1 if $_[0] =~ /^today$/i;
    $_[0] = 99999999 if $_[0] =~ /^tba$/i;
    $_[0] = "${1}9999" if $_[0] =~ /^([0-9]{4})$/;
    $_[0] = "${1}${2}99" if $_[0] =~ /^([0-9]{4})-([0-9]{2})$/;
    $_[0] = "${1}${2}$3" if $_[0] =~ /^([0-9]{4})-([0-9]{2})-([0-9]{2})$/;
    return 1 if $_[0] eq 1;
    _validate_rdate($_[0]);
}


sub _validate_extlinks($t) {
    my $L = \%VNDB::ExtLinks::LINKS;
    my %sites = map +($_, $L->{$_}), grep $L->{$_}{ent} =~ /$t/i, keys %$L;
    +{ default => [], type => 'array', unique => sub {
        $sites{$_[0]{site}}{ent} =~ /\U$t/ ? "$_[0]{site}$_[0]{value}" : $_[0]{site}
    }, values => {
        type => 'hash',
        keys => { site => { enum => \%sites }, value => { maxlength => 512 } },
        func => sub {
            my $re = $sites{$_[0]{site}}{full_regex};
            return 1 if !$re;
            return 0 if sprintf($sites{$_[0]{site}}{fmt}, $_[0]{value}) !~ $re;
            $_[0]{value} = (grep defined, @{^CAPTURE})[0];
            1
        }
    } };
}


# returns true if this request originated from the same site, i.e. not an external referer.
sub samesite { !!tuwf->reqCookie('samesite') }

# returns true if this request is for an /api/ URL.
sub is_api { !$main::NOAPI && ($main::ONLYAPI || tuwf->reqPath =~ /^\/api\//) }

# Test uniqueness of a username in the database. Usernames with similar
# homographs are considered duplicate.
# (Would be much faster and safer to do this normalization in the DB and put a
# unique constraint on the normalized name, but we have a bunch of existing
# username clashes that I can't just change)
sub is_unique_username {
    my($name, $excludeid) = @_;
    my sub norm {
        # lowercase, normalize 'i1l' and '0o'
        sql "regexp_replace(regexp_replace(lower(", $_[0], "), '[1l]', 'i', 'g'), '0', 'o', 'g')";
    };
    !tuwf->dbVali('SELECT 1 FROM users WHERE', norm('username'), '=', norm(\$name),
        $excludeid ? ('AND id <>', \$excludeid) : ());
}


# Lookup IP and return an 'ipinfo' DB string.
sub ipinfo {
    my $ip = shift || tuwf->reqIP;
    state $db = config->{location_db} && do {
        require Location;
        Location::init(config->{location_db});
    };
    sub esc { ($_[0]//'') =~ s/([,()\\'"])/\\$1/rg }
    return sprintf "(%s,,,,,,,)", esc $ip if !$db;

    my sub f { Location::lookup_network_has_flag($db, $ip, "LOC_NETWORK_FLAG_$_[0]") ? 't' : 'f' }
    my $asn = Location::lookup_asn($db, $ip)||'';
    sprintf "(%s,%s,%s,%s,%s,%s,%s,%s)", esc($ip),
        esc(Location::lookup_country_code($db,$ip)),
        $asn, $asn ? esc(Location::get_as_name($db,$asn)) : '',
        f('ANONYMOUS_PROXY'), f('SATELLITE_PROVIDER'), f('ANYCAST'), f('DROP');
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
#
# Also supports compiling with multiple $when's in a single call:
#
#   my ($IN, $OUT) = form_compile 'in', 'out', { .. };
#
sub form_compile {
    my $schema = pop;
    my @l = map tuwf->compile({ type => 'hash', keys => _stripwhen $_, $schema }), @_;
    wantarray ? @l : $l[0];
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
    return if !@missing;
    # If this is a js_api, return a more helpful error message
    if (tuwf->reqPath =~ /^\/js\//) {
        tuwf->resJSON({_err => "Invalid reference to ".join(', ', @missing)});
        tuwf->done;
    }
    croak "Invalid database IDs: ".join(',', @missing);
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

    return auth->permUsermod || (auth && $entry->{id} eq auth->uid) if $type eq 'u';
    return auth->permDbmod if $type eq 'd';

    if($type eq 't') {
        return 1 if auth->permBoardmod;
        return 0 if !auth->permBoard || (global_settings->{lockdown_board} && !auth->isMod);
        if(!$entry->{id}) {
            # Allow at most 5 new threads per day per user.
            return auth && tuwf->dbVali('SELECT count(*) < ', \5, 'FROM threads_posts WHERE num = 1 AND date > NOW()-\'1 day\'::interval AND uid =', \auth->uid);
        } elsif(!$entry->{num}) {
            die "Can't do authorization test when 'locked' field isn't present" if !exists $entry->{locked};
            return !$entry->{locked};
        } else {
            die "Can't do authorization test when hidden/date/user_id fields aren't present"
                if !exists $entry->{hidden} || !exists $entry->{date} || !exists $entry->{user_id};
            # beware: for threads the 'hidden' field is a non-undef boolean flag, for posts it is a possibly-undef text field.
            my $hidden = $entry->{id} =~ /^t/ && $entry->{num} == 1 ? $entry->{hidden} : defined $entry->{hidden};
            return auth && ($entry->{user_id}//'') eq auth->uid && !$hidden && $entry->{date} > time-config->{board_edit_time};
        }
    }

    if($type eq 'w') {
        return 1 if auth->permBoardmod;
        return auth->permReview && (!global_settings->{lockdown_board} || auth->isMod) if !$entry->{id};
        return auth && $entry->{user_id} && auth->uid eq $entry->{user_id};
    }

    if($type eq 'g' || $type eq 'i') {
        return 1 if auth->permTagmod;
        return auth->permEdit if !$entry->{id};
        die if !exists $entry->{entry_hidden} || !exists $entry->{entry_locked};
        # Let users edit their own tags/traits while it's still pending approval.
        return auth && $entry->{entry_hidden} && !$entry->{entry_locked}
            && tuwf->dbVali('SELECT 1 FROM changes WHERE itemid =', \$entry->{id}, 'AND rev = 1 AND requester =', \auth->uid);
    }

    die "Can't do authorization test when entry_hidden/entry_locked fields aren't present"
        if $entry->{id} && (!exists $entry->{entry_hidden} || !exists $entry->{entry_locked});

    auth->permDbmod || (auth->permEdit && !global_settings->{lockdown_edit} && !($entry->{entry_hidden} || $entry->{entry_locked}));
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
        my($view, $token) = (tuwf->reqGet('view')||'') =~ /^([^-]*)-(.+)$/;

        # Abort this request and redirect if the token is invalid.
        if(length($view) && (!samesite || !length($token) || !auth->csrfcheck($token, 'view'))) {
            my $qs = join '&', map { my $k=$_; my @l=tuwf->reqGets($k); map uri_escape($k).'='.uri_escape($_), @l } grep $_ ne 'view', tuwf->reqGets();
            tuwf->resInit;
            tuwf->resRedirect(tuwf->reqPath().($qs?"?$qs":''), 'temp');
            tuwf->done;
        }

        my($sp, $ts, $ns) = ($view||'') =~ /^([0-2])?([sS]?)([nN]?)$/;
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


# Object returned by the 'searchquery' validation, has some handy methods for generating SQL.
package VNWeb::Validate::SearchQuery {
    use TUWF;
    use VNWeb::DB;

    sub query_encode { $_[0][0] }
    sub TO_JSON { $_[0][0] }

    sub words {
        $_[0][1] //= length $_[0][0]
            ? [ map s/%//rg, tuwf->dbVali('SELECT search_query(', \$_[0][0], ')')->@* ]
            : []
    }

    use overload bool => sub { $_[0]->words->@* > 0 };
    use overload '""' => sub { $_[0][0]//'' };

    sub _isvndbid { my $l = $_[0]->words; @$l == 1 && $l->[0] =~ /^[vrpcsgi]$num$/ }

    sub where {
        my($self, $type, $nothid) = @_;
        my $lst = $self->words;
        my @keywords = map sql('sc.label LIKE', \('%'.sql_like($_).'%')), @$lst;
        +(
            $type ? "sc.id BETWEEN '${type}1' AND vndbid_max('$type')" : (),
            $nothid ? 'sc.prio <> 4' : (),
            $self->_isvndbid()
                ? (sql 'sc.id =', \$lst->[0], 'OR', sql_and(@keywords))
                : @keywords
        )
    }

    sub sql_where {
        my($self, $type, $id, $subid) = @_;
        return '1=1' if !$self;
        sql 'EXISTS(SELECT 1 FROM search_cache sc WHERE', sql_and(
            sql('sc.id =', $id), $subid ? sql('sc.subid =', $subid) : (),
            $self->where($type),
        ), ')';
    }

    # Returns a subquery that can be joined to get the search score.
    # Columns (id, subid, score)
    sub sql_score {
        my($self, $type) = @_;
        my $lst = $self->words;
        my $q = join '', @$lst;
        sql '(SELECT id, subid, max(sc.prio * (', VNWeb::DB::sql_join('+',
                $self->_isvndbid() ? sql('CASE WHEN sc.id =', \$q, 'THEN 1+1 ELSE 0 END') : (),
                sql('CASE WHEN sc.label LIKE', \(sql_like($q).'%'), 'THEN 1::float/(1+1) ELSE 0 END'),
                sql('similarity(sc.label,', \$q, ')'),
            ), ')) AS score
            FROM search_cache sc
           WHERE', sql_and($self->where($type)), '
           GROUP BY id, subid
        )';
    }

    # Optionally returns a JOIN clause for sql_score, aliassed 'sc'
    no warnings 'redefine';
    sub sql_join {
        my($self, $type, $id, $subid) = @_;
        return '' if !$self;
        sql 'JOIN', $self->sql_score($type), 'sc ON sc.id =', $id, $subid ? ('AND sc.subid =', $subid) : ();
    }

    # Same as sql_join(), but accepts an array of SearchQuery objects that are OR'ed together.
    sub sql_joina {
        my($lst, $type, $id, $subid) = @_;
        sql 'JOIN (
            SELECT id, subid, max(score) AS score
              FROM (', VNWeb::DB::sql_join('UNION ALL', map sql('SELECT * FROM', $_->sql_score($type), 'x'), @$lst), ') x
             GROUP BY id, subid
          ) sc ON sc.id =', $id, $subid ? ('AND sc.subid =', $subid) : ();
    }
};

1;
