package VNDB::Skins;

use v5.26;
use warnings;
use Exporter 'import';
our @EXPORT = ('skins');

my $ROOT = $INC{'VNDB/Skins.pm'} =~ s{/lib/VNDB/Skins\.pm$}{}r;

my $skins;

sub skins {
    $skins ||= do { +{ map {
        my $skin = /\/([^\/]+)\/conf/ ? $1 : die;
        my %o;
        open my $F, '<:utf8', $_ or die $!;
        while(<$F>) {
            chomp;
            s/\r//g;
            s{[\t\s]*//.+$}{};
            next if !/^([a-z0-9]+)[\t\s]+(.+)$/;
            $o{$1} = $2;
        }
        +( $skin, \%o )
    } glob "$ROOT/static/s/*/conf" } };
    $skins;
}

1;
