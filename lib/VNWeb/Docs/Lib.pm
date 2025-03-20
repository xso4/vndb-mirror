package VNWeb::Docs::Lib;

use VNWeb::Prelude;
use VNDB::Skins;

our @EXPORT = qw/enrich_html/;


my @special_perms = qw/boardmod dbmod usermod tagmod/;

sub _moderators {
    my $cols = sql_comma map "perm_$_", @special_perms;
    my $where = sql_or map "perm_$_", @special_perms;
    state $l //= tuwf->dbAlli("SELECT u.id, username, $cols FROM users u JOIN users_shadow us ON us.id = u.id WHERE $where ORDER BY u.id LIMIT 100");

    fragment sub {
        dl_ sub {
            for my $u (@$l) {
                dt_ sub { a_ href => "/$u->{id}", $u->{username} };
                dd_ @special_perms == grep($u->{"perm_$_"}, @special_perms) ? 'admin'
                    : join ', ', grep $u->{"perm_$_"}, @special_perms;
            }
        }
    }
}


sub _skincontrib {
    my %users;
    push $users{ skins->{$_}{userid} }->@*, [ $_, skins->{$_}{name} ]
        for sort { skins->{$a}{name} cmp skins->{$b}{name} } keys skins->%*;

    my $u = tuwf->dbAlli('SELECT id, username FROM users WHERE id IN', [keys %users], 'ORDER BY id');

    fragment sub {
        dl_ sub {
            for my $u (@$u) {
                dt_ sub { a_ href => "/$u->{id}", $u->{username} };
                dd_ sub {
                    join_ ', ', sub { a_ href => "?skin=$_->[0]", $_->[1] }, $users{$u->{id}}->@*
                }
            }
        }
    }
}


sub enrich_html {
    my $html = shift;

    $html =~ s{^:MODERATORS:}{_moderators}me;
    $html =~ s{^:SKINCONTRIB:}{_skincontrib}me;

    $html
}

1;
