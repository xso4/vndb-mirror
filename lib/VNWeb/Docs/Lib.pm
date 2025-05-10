package VNWeb::Docs::Lib;

use VNWeb::Prelude;
use VNDB::Skins;

our @EXPORT = qw/enrich_html/;


my @special_perms = qw/boardmod dbmod usermod tagmod/;

sub _moderators {
    my $cols = join ',', map "perm_$_", @special_perms;
    my $where = join ' or ', map "perm_$_", @special_perms;
    state $l //= fu->sql("SELECT u.id, username, $cols FROM users u JOIN users_shadow us ON us.id = u.id WHERE $where ORDER BY u.id LIMIT 100")->cache(0)->allh;

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
    state $stats = fu->sql('SELECT skin, count(*) FROM users_prefs GROUP BY skin')->cache(0)->kvv;
    my %users;
    push $users{ skins->{$_}{userid} }->@*, [ $_, skins->{$_}{name} ]
        for sort { skins->{$a}{name} cmp skins->{$b}{name} } keys skins->%*;

    my $u = fu->SQL('SELECT id,', USER, 'FROM users u WHERE id', IN [keys %users], 'ORDER BY id')->allh;

    fragment sub {
        dl_ sub {
            for my $u (@$u) {
                dt_ sub { user_ $u };
                dd_ sub {
                    join_ ', ', sub {
                        a_ href => "?skin=$_->[0]", $_->[1];
                        small_ " $stats->{$_->[0]}" if $stats->{$_->[0]};
                    }, $users{$u->{id}}->@*
                }
            }
        }
    }
}


sub enrich_html {
    my $html = shift;

    $html =~ s{(^|<p>):MODERATORS:(</p>)?}{_moderators}me;
    $html =~ s{(^|<p>):SKINCONTRIB:(</p>)?}{_skincontrib}me;

    $html
}

1;
