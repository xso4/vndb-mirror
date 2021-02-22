# Importing this module is equivalent to:
#
#  use v5.26;
#  use warnings;
#  use utf8;
#
#  use TUWF ':html5_', 'mkclass', 'xml_string', 'xml_escape';
#  use Exporter 'import';
#  use Time::HiRes 'time';
#  use List::Util 'min', 'max', 'sum';
#  use POSIX 'ceil', 'floor', 'strftime';
#
#  use VNDB::BBCode;
#  use VNDB::Types;
#  use VNDB::Config;
#  use VNDB::Func;
#  use VNDB::ExtLinks;
#  use VNWeb::Auth;
#  use VNWeb::HTML;
#  use VNWeb::DB;
#  use VNWeb::Validation;
#  use VNWeb::Elm;
#  use VNWeb::TableOpts;
#
# + A few other handy tools.
#
# WARNING: This should not be used from the above modules.
package VNWeb::Prelude;

use strict;
use warnings;
use feature ':5.26';
use utf8;
use VNWeb::Elm;
use VNWeb::Auth;
use VNWeb::DB;
use TUWF;
use JSON::XS;


sub import {
    my $c = caller;

    strict->import;
    warnings->import;
    feature->import(':5.26');
    utf8->import;

    die $@ if !eval <<"    EOM;";
    package $c;

    use TUWF ':html5_', 'mkclass', 'xml_string', 'xml_escape';
    use Exporter 'import';
    use Time::HiRes 'time';
    use List::Util 'min', 'max', 'sum';
    use POSIX 'ceil', 'floor', 'strftime';

    use VNDB::BBCode;
    use VNDB::Types;
    use VNDB::Config;
    use VNDB::Func;
    use VNDB::ExtLinks;
    use VNWeb::Auth;
    use VNWeb::HTML;
    use VNWeb::DB;
    use VNWeb::Validation;
    use VNWeb::Elm;
    use VNWeb::TableOpts;
    1;
    EOM;

    no strict 'refs';
    *{$c.'::RE'} = *RE;
    *{$c.'::in'} = \&in;
    *{$c.'::idcmp'} = \&idcmp;
    *{$c.'::dbobj'} = \&dbobj;
}


# Regular expressions for use in path registration
my $num = qr{[1-9][0-9]{0,6}}; # Allow up to 10 mil, SQL vndbid type can't handle more than 2^26-1 (~ 67 mil).
my $id = qr{(?<id>$num)};
my $rev = qr{(?:\.(?<rev>$num))};
our %RE = (
    num  => qr{(?<num>$num)},
    uid  => qr{u$id},
    vid  => qr{v$id},
    rid  => qr{r$id},
    sid  => qr{s$id},
    cid  => qr{c$id},
    pid  => qr{p$id},
    iid  => qr{i$id},
    did  => qr{d$id},
    tid  => qr{(?<id>t$num)},
    gid  => qr{g$id},
    wid  => qr{(?<id>w$num)},
    imgid=> qr{(?<id>(?:ch|cv|sf)$num)},
    vrev => qr{v$id$rev?},
    rrev => qr{r$id$rev?},
    prev => qr{p$id$rev?},
    srev => qr{s$id$rev?},
    crev => qr{c$id$rev?},
    drev => qr{d$id$rev?},
    postid => qr{(?<id>t$num)\.(?<num>$num)},
);


# Simple "is this element in the array?" function, using 'eq' to test equality.
# Supports both an @array and \@array.
# Usage:
#
#   my $contains_hi = in 'hi', qw/ a b hi c /; # true
#
sub in {
    my($q, @a) = @_;
    $_ eq $q && return 1 for map ref $_ eq 'ARRAY' ? @$_ : ($_), @a;
    0
}


# Compare two vndbids, using proper numeric order
sub idcmp($$) {
    my($a1, $a2) = $_[0] =~ /^([a-z]+)([0-9]+)$/;
    my($b1, $b2) = $_[1] =~ /^([a-z]+)([0-9]+)$/;
    $a1 cmp $b1 || $a2 <=> $b2
}


# Returns very generic information on a DB entry object.
# Only { id, title, entry_hidden, entry_locked } for now.
# Suitable for passing to HTML::framework_'s dbobj argument.
sub dbobj {
    my($type, $id) = @_;

    my sub item {
        my($table, $title) = @_;
        tuwf->dbRowi('SELECT id,', $title, ' AS title, hidden AS entry_hidden, locked AS entry_locked FROM', $table, 'WHERE id =', \$id);
    };

    !$type ? undef :
        $type eq 'u' ? tuwf->dbRowi('SELECT id, ', sql_user(), 'FROM users u WHERE id =', \$id) :
        $type eq 'p' ? item producers => 'name' :
        $type eq 'v' ? item vn        => 'title' :
        $type eq 'r' ? item releases  => 'title' :
        $type eq 'c' ? item chars     => 'name' :
        $type eq 's' ? item staff     => '(SELECT name FROM staff_alias WHERE aid = staff.aid)' :
        $type eq 'd' ? item docs      => 'title' : die;
}

1;
