package VNDB::Skins;

use v5.26;
use warnings;
use Exporter 'import';
our @EXPORT = ('skins');

my $ROOT = $INC{'VNDB/Skins.pm'} =~ s{/lib/VNDB/Skins\.pm$}{}r;

my $skins;

sub skins {
    $skins ||= do { +{ map {
        my $skin = /\/([^\/]+)\.sass/ ? $1 : die;
        my %o;
        open my $F, '<:utf8', $_ or die $!;
        if(<$F> !~ qr{^// *userid: *([0-9]+) *name: *(.+)}) {
            warn "Invalid skin: $skin\n";
            ()
        } else {
            +( $skin, { userid => $1, name => $2 })
        }
    } glob "$ROOT/css/skins/*.sass" } };
    $skins;
}

1;
