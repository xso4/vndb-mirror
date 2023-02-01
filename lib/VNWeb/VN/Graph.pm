package VNWeb::VN::Graph;

use VNWeb::Prelude;
use VNWeb::Graph;


TUWF::get qr{/$RE{vid}/rg}, sub {
    my $id = tuwf->capture(1);
    my $num = tuwf->validate(get => num => { uint => 1, onerror => 15 })->data;
    my $unoff = tuwf->validate(get => unoff => { default => 1, anybool => 1 })->data;
    my $v = dbobj $id;

    my $has = tuwf->dbRowi('SELECT bool_or(official) AS official, bool_or(not official) AS unofficial FROM vn_relations WHERE id =', \$id, 'GROUP BY id');
    $unoff = 1 if !$has->{official};

    # Big list of { id0, id1, relation } hashes.
    # Each relation is included twice, with id0 and id1 reversed.
    my $where = $unoff ? '1=1' : 'vr.official';
    my $rel = tuwf->dbAlli(q{
        WITH RECURSIVE rel(id0, id1, relation, official) AS (
            SELECT id, vid, relation, official FROM vn_relations vr WHERE id =}, \$id, 'AND', $where, q{
            UNION
            SELECT id, vid, vr.relation, vr.official FROM vn_relations vr JOIN rel r ON vr.id = r.id1 WHERE}, $where, q{
        ) SELECT * FROM rel ORDER BY id0
    });
    return tuwf->resNotFound if !@$rel;

    # Fetch the nodes
    my $nodes = gen_nodes $id, $rel, $num;
    enrich_merge id => sql("SELECT id, title, c_released, array_to_string(c_languages, '/') AS lang FROM", vnt, "v WHERE id IN"), values %$nodes;

    my $total_nodes = keys { map +($_->{id0},1), @$rel }->%*;
    my $visible_nodes = keys %$nodes;

    my @lines;
    my $params = "?num=$num&unoff=$unoff";
    for my $n (sort { idcmp $a->{id}, $b->{id} } values %$nodes) {
        my $title = val_escape shorten $n->{title}, 27;
        my $tooltip = val_escape $n->{title};
        my $date = rdate $n->{c_released};
        my $lang = $n->{lang}||'N/A';
        my $nodeid = $n->{distance} == 0 ? 'id = "graph_current", ' : '';
        push @lines,
            qq|n$n->{id} [ $nodeid URL = "/$n->{id}", tooltip = "$tooltip", label=<|.
            qq|<TABLE CELLSPACING="0" CELLPADDING="2" BORDER="0" CELLBORDER="1" BGCOLOR="#222222">|.
            qq|<TR><TD COLSPAN="2" ALIGN="CENTER" CELLPADDING="3"><FONT POINT-SIZE="9">  $title  </FONT></TD></TR>|.
            qq|<TR><TD> $date </TD><TD> $lang </TD></TR>|.
            qq|</TABLE>> ]|;

        push @lines, node_more $n->{id}, "/$n->{id}/rg$params", scalar grep !$nodes->{$_}, $n->{rels}->@*;
    }

    $rel = [ grep $nodes->{$_->{id0}} && $nodes->{$_->{id1}}, @$rel ];
    my $dot = gen_dot \@lines, $nodes, $rel, \%VN_RELATION;

    framework_ title => "Relations for $v->{title}", dbobj => $v, tab => 'rg',
    sub {
        div_ class => 'mainbox', style => 'float: left; min-width: 100%', sub {
            h1_ "Relations for $v->{title}";
            p_ sub {
                txt_ sprintf "Displaying %d out of %d related visual novels.", $visible_nodes, $total_nodes;
                debug_ +{ nodes => $nodes, rel => $rel };
                br_;
                if($has->{official}) {
                    if($unoff) {
                        txt_ 'Show / ';
                        a_ href => "?num=$num&unoff=0", 'Hide';
                    } else {
                        a_ href => "?num=$num&unoff=1", 'Show';
                        txt_ ' / Hide';
                    }
                    txt_ ' unofficial relations. ';
                    br_;
                }
                if($total_nodes > 10) {
                    txt_ 'Adjust graph size: ';
                    join_ ', ', sub {
                        if($_ == min $num, $total_nodes) {
                            txt_ $_ ;
                        } else {
                            a_ href => "/$id/rg?num=$_", $_;
                        }
                    }, grep($_ < $total_nodes, 10, 15, 25, 50, 75, 100, 150, 250, 500, 750, 1000), $total_nodes;
                }
                txt_ '.';
            } if $total_nodes > 10 || $has->{unofficial};
            p_ class => 'center', sub { lit_ dot2svg $dot };
        };
        clearfloat_;
    };
};

1;
