package VNWeb::ULists::Lib;

use VNWeb::Prelude;
use Exporter 'import';

our @EXPORT = qw/ulists_own/;

# Do we have "ownership" access to this users' list (i.e. can we edit and see private stuff)?
sub ulists_own {
    auth->permUsermod || (auth && auth->uid eq shift)
}

1;
