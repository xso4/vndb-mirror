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
    *{$c.'::dbobj'} = \&dbobj;
}


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


# Returns very generic information on a DB entry object.
# Only { id, title, entry_hidden, entry_locked } for now.
# Suitable for passing to HTML::framework_'s dbobj argument.
# TODO: Merge with SQL's item_info() or something.
sub dbobj {
    my($id) = @_;

    my sub item {
        my($table, $title) = @_;
        tuwf->dbRowi('SELECT id,', $title, ' AS title, hidden AS entry_hidden, locked AS entry_locked FROM', $table, 'WHERE id =', \$id);
    };

    my $o = !$id ? undef :
        $id =~ /^u/ ? tuwf->dbRowi('SELECT id, ', sql_user(), 'FROM users u WHERE id =', \$id) :
        $id =~ /^p/ ? item producers => 'name' :
        $id =~ /^v/ ? item vn        => 'title' :
        $id =~ /^r/ ? item releases  => 'title' :
        $id =~ /^c/ ? item chars     => 'name' :
        $id =~ /^s/ ? item staff     => '(SELECT name FROM staff_alias WHERE aid = staff.aid)' :
        $id =~ /^g/ ? item tags      => 'name' :
        $id =~ /^i/ ? item traits    => 'name' :
        $id =~ /^d/ ? item docs      => 'title' : die;

    $o->{title} = VNWeb::HTML::user_displayname $o if $id =~ /^u/;
    $o;
}

1;
