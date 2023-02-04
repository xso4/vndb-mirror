package VNWeb::Discussions::Elm;

use VNWeb::Prelude;

# Autocompletion search results for boards
elm_api Boards => undef, {
    search => {},
}, sub {
    return elm_Unauth if !auth->permBoard;
    my $q = shift->{search};
    my $qs = sql_like $q;

    my sub item {
        my($tbl, $type, $title, $filt, $query) = @_;
        my $title_score = sql "1+substr_score(lower($title),", \$qs, ')';
        sql 'SELECT',
                $q =~ /^$type$RE{num}$/
                ? sql 'CASE WHEN id =', \$q, 'THEN 0 ELSE', $title_score, 'END'
                : $title_score,
                ',', \$type, "::board_type, id, $title
            FROM", $tbl, "x
           WHERE", $filt, 'AND', sql_or(
               $query, $q =~ /^$type$RE{num}$/ ? sql 'id =', \$q : ());
    }

    elm_BoardResult tuwf->dbPagei({ results => 10, page => 1 },
        'SELECT btype, iid, title
           FROM (',
             sql_join('UNION ALL',
                 (map sql('SELECT 1, ', \$_, '::board_type, NULL::vndbid, NULL'),
                     grep $q eq $_ || $BOARD_TYPE{$_}{txt} =~ /\Q$q/i,
                     grep !$BOARD_TYPE{$_}{dbitem} && ($BOARD_TYPE{$_}{post_perm} eq 'board' || auth->permBoardmod),
                     keys %BOARD_TYPE),
                 item(vnt, 'v', 'title', 'NOT hidden', sql 'c_search LIKE ALL (search_query(', \$q, '))'),
                 item(producerst, 'p', 'name', 'NOT hidden', sql 'c_search LIKE ALL (search_query(', \$q, '))'),
                 item('users', 'u', 'username', 'true', sql 'lower(username) LIKE', \lc "%$qs%"),
             ), ') x(prio, btype, iid, title)
           ORDER BY prio, btype, title'
    )
};

1;
