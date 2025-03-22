# Importing this module is equivalent to:
#
#  use v5.36;
#  use utf8;
#
#  use FU;
#  use FU::Util 'query_encode';
#  use FU::XMLWriter @html5_tags, 'fragment';
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
#  use VNWeb::TableOpts;
#  use VNWeb::TitlePrefs;
#
# + A handy dbobj() function.
#
# WARNING: This should not be used from the above modules.
package VNWeb::Prelude;

use strict;
use warnings;
use feature ':5.36';
use utf8;
use VNWeb::Auth;
use VNWeb::DB;
use FU;

# Only export a subset of ':html5_' functions to avoid bloating symbol tables too much.
our @html5_tags = qw/
    a_ abbr_ article_ b_ br_ button_ dd_ details_ div_ dl_ dt_ em_ fieldset_
    form_ h1_ h2_ h3_ i_ img_ input_ label_ li_ menu_ nav_ option_ p_ section_
    select_ small_ span_ strong_ summary_ table_ tbody_ td_ textarea_ tfoot_
    th_ thead_ tr_ ul_
/;


sub import {
    my $c = caller;

    strict->import;
    warnings->import;
    feature->import(':5.36');
    utf8->import;

    die $@ if !eval <<"    EOM;";
    package $c;

    use FU;
    use FU::Util 'query_encode';
    use FU::XMLWriter \@VNWeb::Prelude::html5_tags, qw/tag_ txt_ lit_ fragment/;
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
    use VNWeb::TableOpts;
    use VNWeb::TitlePrefs;
    1;
    EOM;

    no strict 'refs';
    *{$c.'::dbobj'} = \&dbobj;
    *{$c.'::tuwf'} = \&fu;
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
