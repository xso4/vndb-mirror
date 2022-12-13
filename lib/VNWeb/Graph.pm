package VNWeb::Graph;

# Utility functions for VNWeb::Producers::Graph anv VNWeb::VN::Graph.

use v5.26;
use AnyEvent::Util;
use TUWF::XML 'xml_escape';
use Exporter 'import';
use List::Util 'max';
use VNDB::Config;
use VNDB::Func 'idcmp';

our @EXPORT = qw/gen_nodes dot2svg val_escape node_more gen_dot/;


# Given a starting ID, an array of {id0,id1} relation hashes and a number of
# nodes to be included, returns a hash of (id=>{id, distance, rels}) nodes.
#
# This is basically a breath-first search that prioritizes nodes with fewer
# relations.  Direct relations with the starting node are always included,
# regardless of $num.
sub gen_nodes {
    my($id, $rel, $num) = @_;

    my %rels;
    push $rels{$_->{id0}}->@*, $_->{id1} for @$rel;

    my %nodes;
    my @q = ({ id => $id, distance => 0 });
    while(my $n = shift @q) {
        next if $nodes{$n->{id}};
        last if $num <= 0 && $n->{distance} > 1;
        $num--;
        $n->{rels} = $rels{$n->{id}};
        $nodes{$n->{id}} = $n;
        push @q, map +{ id => $_, distance => $n->{distance}+1 }, sort { $rels{$a}->@* <=> $rels{$b}->@* } grep !$nodes{$_}, $n->{rels}->@*;
    }

    \%nodes;
}


sub dot2svg {
    my($dot) = @_;

    utf8::encode $dot;
    my $e = run_cmd([config->{graphviz_path},'-Tsvg'], '<', \$dot, '>', \my $out, '2>', \my $err)->recv;
    warn "graphviz STDERR: $err\n" if chomp $err;
    $e and die "Failed to run graphviz";

    # - Remove <?xml> declaration and <!DOCTYPE> (not compatible with embedding in HTML5)
    # - Remove comments (unused)
    # - Remove <title> elements (unused)
    # - Remove first <polygon> element (emulates a background color)
    # - Replace stroke and fill attributes with classes (so that coloring is done in CSS)
    # (I used to have an implementation based on XML::Parser, but regexes are so much faster...)
    utf8::decode $out or die;
    $out=~ s/<\?xml.+?\?>//r
        =~ s/<!DOCTYPE[^>]*>//r
        =~ s/<!--.*?-->//srg
        =~ s/<title>.+?<\/title>//gr
        =~ s/<polygon.+?\/>//r
        =~ s/(?:stroke|fill)="([^"]+)"/$1 eq '#111111' ? 'class="border"' : $1 eq '#222222' ? 'class="nodebg"' : ''/egr;
}


sub val_escape { $_[0] =~ s/&/&amp;/rg =~ s/\\/\\\\/rg =~ s/"/&quot;/rg =~ s/</&lt;/rg =~ s/>/&gt;/rg }


sub node_more {
    my($id, $url, $number) = @_;
    return () if !$number;
    (
        qq|\tns$id [ URL = "$url", label="$number more..." ]|,
        qq|\tn$id -- ns$id [ dir = "forward", style = "dashed" ]|
    )
}


sub gen_dot {
    my($lines, $nodes, $rel, $rel_types) = @_;

    # Attempt to figure out a good 'rankdir' to minimize the width of the
    # graph. Ideally we'd just generate two graphs and pick the least wide one,
    # but that's way too slow. Graphviz tends to put adjacent nodes next to
    # each other, so going for the LR (left-right) rank order tends to work
    # better with large fan-out, while TB (top-bottom) often results in less
    # wide graphs for large depths.
    #my $max_distance = max map $_->{distance}, values %$nodes;
    my $max_fanout = max map scalar grep($nodes->{$_}, $_->{rels}->@*), values %$nodes;
    my $rankdir = $max_fanout > 6 ? 'LR' : 'TB';

    for (@$rel) {
        next if idcmp($_->{id0}, $_->{id1}) < 0;
        my $r1 = $rel_types->{$_->{relation}};
        my $r2 = $rel_types->{ $r1->{reverse} };
        my $style = exists $_->{official} && !$_->{official} ? 'style="dotted", ' : '';
        push @$lines,
            qq|n$_->{id0} -- n$_->{id1} [$style|.(
            $r1 == $r2  ? qq|label="$r1->{txt}"| :
            $r1->{pref} ? qq|headlabel="$r1->{txt}", dir = "forward"| :
            $r2->{pref} ? qq|taillabel="$r2->{txt}", dir = "back"| :
                          qq|headlabel="$r1->{txt}", taillabel="$r2->{txt}"|
            ).']';
    }

    qq|graph rgraph {\n|.
    qq|\trankdir = "$rankdir"\n|.
    qq|\tnode [ fontname = "Arial", shape = "plaintext", fontsize = 8, color = "#111111" ]\n|.
    qq|\tedge [ labeldistance = 2.5, labelangle = -20, labeljust = 1, minlen = 2, dir = "both",|.
    qq| fontname = "Arial", fontsize = 7, arrowsize = 0.7, color = "#111111" ]\n|.
    join("\n", @$lines).
    qq|\n}\n|;
}

1;
