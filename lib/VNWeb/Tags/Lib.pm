package VNWeb::Tags::Lib;

use VNWeb::Prelude;
use Exporter 'import';

our @EXPORT = qw/ tagscore_ enrich_group /;

sub tagscore_ {
    my($s, $ign) = @_;
    div_ mkclass(tagscore => 1, negative => $s < 0, ignored => $ign), sub {
        span_ sprintf '%.1f', $s;
        div_ style => sprintf('width: %.0fpx', abs $s/3*30), '';
    };
}


# Add a 'group' name for traits
sub enrich_group {
    my($type, @lst) = @_;
    enrich_merge id => 'SELECT t.id, g.name AS "group" FROM traits t JOIN traits g ON g.id = t."group" WHERE t.id IN', @lst if $type eq 'i';
}

1;
