package VNWeb::Producers::Graph;

use VNWeb::Prelude;
use VNWeb::Graph;


TUWF::get qr{/$RE{pid}/rg}, sub {
    my $id = tuwf->capture(1);
    my $num = tuwf->validate(get => num => { uint => 1, onerror => 15 })->data;
    my $p = tuwf->dbRowi('SELECT id, name, original, hidden AS entry_hidden, locked AS entry_locked FROM producers WHERE id =', \$id);

    # Big list of { id0, id1, relation } hashes.
    # Each relation is included twice, with id0 and id1 reversed.
    my $rel = tuwf->dbAlli(q{
        WITH RECURSIVE rel(id0, id1, relation) AS (
            SELECT id, pid, relation FROM producers_relations WHERE id =}, \$id, q{
            UNION
            SELECT id, pid, pr.relation FROM producers_relations pr JOIN rel r ON pr.id = r.id1
        ) SELECT * FROM rel ORDER BY id0
    });
    return tuwf->resNotFound if !@$rel;

    # Fetch the nodes
    my $nodes = gen_nodes $id, $rel, $num;
    enrich_merge id => 'SELECT id, name, lang, type FROM producers WHERE id IN', values %$nodes;

    my $total_nodes = keys { map +($_->{id0},1), @$rel }->%*;
    my $visible_nodes = keys %$nodes;

    my @lines;
    my $params = $num == 15 ? '' : "?num=$num";
    for my $n (sort { idcmp $a->{id}, $b->{id} } values %$nodes) {
        my $name = val_escape shorten $n->{name}, 27;
        my $tooltip = val_escape $n->{name};
        my $nodeid = $n->{distance} == 0 ? 'id = "graph_current", ' : '';
        push @lines,
            qq|n$n->{id} [ $nodeid URL = "/$n->{id}", tooltip = "$tooltip", label=<|.
            qq|<TABLE CELLSPACING="0" CELLPADDING="2" BORDER="0" CELLBORDER="1" BGCOLOR="#222222">|.
            qq|<TR><TD COLSPAN="2" ALIGN="CENTER" CELLPADDING="3"><FONT POINT-SIZE="9">  $name  </FONT></TD></TR>|.
            qq|<TR><TD ALIGN="CENTER"> $LANGUAGE{$n->{lang}} </TD><TD ALIGN="CENTER"> $PRODUCER_TYPE{$n->{type}} </TD></TR>|.
            qq|</TABLE>> ]|;

        push @lines, node_more $n->{id}, "/$n->{id}/rg$params", scalar grep !$nodes->{$_}, $n->{rels}->@*;
    }

    $rel = [ grep $nodes->{$_->{id0}} && $nodes->{$_->{id1}}, @$rel ];
    my $dot = gen_dot \@lines, $nodes, $rel, \%PRODUCER_RELATION;

    framework_ title => "Relations for $p->{name}", type => 'p', dbobj => $p, tab => 'rg',
    sub {
        div_ class => 'mainbox', style => 'float: left; min-width: 100%', sub {
            h1_ "Relations for $p->{name}";
            p_ sub {
                txt_ sprintf "Displaying %d out of %d related producers.", $visible_nodes, $total_nodes;
                debug_ +{ nodes => $nodes, rel => $rel };
                br_;
                txt_ "Adjust graph size: ";
                join_ ', ', sub {
                    if($_ == min $num, $total_nodes) {
                        txt_ $_ ;
                    } else {
                        a_ href => "/$id/rg?num=$_", $_;
                    }
                }, grep($_ < $total_nodes, 10, 15, 25, 50, 75, 100, 150, 250, 500, 750, 1000), $total_nodes;
                txt_ '.';
            } if $total_nodes > 10;
            p_ class => 'center', sub { lit_ dot2svg $dot };
        };
        clearfloat_;
    };
};

1;
