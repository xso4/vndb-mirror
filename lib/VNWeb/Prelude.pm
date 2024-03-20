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
#  use VNWeb::JS;
#  use VNWeb::Elm;
#  use VNWeb::TableOpts;
#  use VNWeb::TitlePrefs;
#
# + A handy dbobj() function.
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
    use VNWeb::JS;
    use VNWeb::Elm;
    use VNWeb::TableOpts;
    use VNWeb::TitlePrefs;
    1;
    EOM;

    no strict 'refs';
    *{$c.'::dbobj'} = \&dbobj;
}


# Returns very generic information on a DB entry object.
# Suitable for passing to HTML::framework_'s dbobj argument.
sub dbobj {
    my($id) = @_;

    return undef if !$id;
    if($id =~ /^u/) {
        my $o = tuwf->dbRowi('SELECT id, username IS NULL AS entry_hidden,', sql_user(), 'FROM users u WHERE id =', \$id);
        $o->{title} = [(undef, VNWeb::HTML::user_displayname $o)x2];
        return $o;
    }

    tuwf->dbRowi('SELECT', \$id, 'AS id, title, hidden AS entry_hidden, locked AS entry_locked FROM', VNWeb::TitlePrefs::item_info(\$id, 'NULL'), ' x');
}

1;
