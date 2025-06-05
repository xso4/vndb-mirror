package VNWeb::VN::Graph;

use VNWeb::Prelude;
use VNWeb::Graph;
use VNWeb::VN::Lib;


FU::get qr{/$RE{vid}/rg}, sub($id) {
    not_moe;
    my $num = fu->query(num => { uint => 1, onerror => 15 });
    my $unoff = fu->query(unoff => { default => 1, anybool => 1 });
    my $v = dbobj $id;

    my $has = fu->SQL('SELECT bool_or(official) AS official, bool_or(not official) AS unofficial FROM vn_relations WHERE id =', $id, 'GROUP BY id')->rowh;
    $unoff = 1 if !$has->{official};

    # Big list of { id0, id1, relation } hashes.
    # Each relation is included twice, with id0 and id1 reversed.
    my $where = RAW $unoff ? '1=1' : 'vr.official';
    my $rel = fu->SQL(q{
        WITH RECURSIVE rel(id0, id1, relation, official) AS (
            SELECT id, vid, relation, official FROM vn_relations vr WHERE id =}, $id, 'AND', $where, q{
            UNION
            SELECT id, vid, vr.relation, vr.official FROM vn_relations vr JOIN rel r ON vr.id = r.id1 WHERE}, $where, q{
        ) SELECT * FROM rel ORDER BY id0
    })->allh;
    fu->notfound if !@$rel;

    # Fetch the nodes
    my $nodes = gen_nodes $id, $rel, $num;
    fu->enrich(merge => 1, SQL("SELECT id, title[2], c_released, array_to_string(c_languages, '/') AS lang FROM", VNT, "v WHERE id"), [values %$nodes]);

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

    framework_ title => "Relations for $v->{title}[1]", dbobj => $v, tab => 'rg',
    sub {
        article_ class => 'relgraph', sub {
            h1_ "Relations for $v->{title}[1]";
            a_ href => "/$v->{id}/rgi", 'Interactive graph »';
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


FU::get qr{/$RE{vid}/rgi}, sub($id) {
    my $v = dbobj $id;

    # Big list of { id0, id1, relation, official } hashes.
    # Each relation is included twice, with id0 and id1 reversed.
    my $rel = fu->SQL(q{
        WITH RECURSIVE rel(id0, id1, relation, official) AS (
            SELECT id, vid, relation, official FROM vn_relations vr WHERE id =}, $v->{id}, q{
            UNION
            SELECT id, vid, vr.relation, vr.official FROM vn_relations vr JOIN rel r ON vr.id = r.id1
        ) SELECT * FROM rel ORDER BY id0
    })->allh;
    fu->notfound if !@$rel;

    # Get rid of duplicate relations and convert to a more efficient array-based format.
    # For directional relations, keep the one that is preferred ("pref"), for unidirectional relations, keep the one with the lowest id0.
    $rel = [
        map [ @{$_}{qw/ id0 id1 relation official /} ],
        grep $VN_RELATION{$_->{relation}}{pref} || ($VN_RELATION{$_->{relation}}{reverse} eq $_->{relation} && idcmp($_->{id0}, $_->{id1}) < 0), @$rel
    ];

    # Fetch the nodes
    my %nodes = map +($_, {id => $_}), map @{$_}[0,1], @$rel;
    fu->enrich(merge => 1, SQL('
        SELECT id, title[2], title[4] AS alttitle, c_released AS released,', VNIMAGE, ', c_languages AS languages
          FROM', VNT, 'v WHERE id'
    ), [values %nodes]);
    enrich_vnimage [values %nodes];

    # compress image info a bit
    for (values %nodes) {
        my $i = delete $_->{vnimage};
        $_->{image} = $i && [
            imgurl($i->{id}, $i->{width} > config->{cv_size}[0] || $i->{height} > config->{cv_size}[1] ? 't' : ''),
            $i->{sexual},
            $i->{violence}
        ]
    }

    framework_ title => "Relations for $v->{title}[1]", dbobj => $v, tab => 'rg',
    sub {
        article_ sub {
            h1_ "Relations for $v->{title}[1]";
            div_ widget(VNGraph => {
                sexual   => 0+(auth->pref('max_sexual')||0),
                violence => 0+(auth->pref('max_violence')||0),
                main     => $v->{id},
                nodes    => [values %nodes],
                rels     => $rel,
            }), ''
        }
    };
};

1;
