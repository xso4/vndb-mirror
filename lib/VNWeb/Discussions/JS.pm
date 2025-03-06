package VNWeb::Discussions::JS;

use VNWeb::Prelude;

# Autocompletion search results for boards
js_api Boards => {search => { searchquery => 1 }}, sub {
    return tuwf->resDenied if !auth->permBoard;
    my $q = shift->{search};
    my $qs = sql_like "$q";

    my $uscore = sql 'similarity(username, ', \$qs, ')';
    $uscore = sql 'CASE WHEN id =', \$qs, 'THEN 1+1 ELSE', $uscore, 'END' if $qs =~ /^u$RE{num}$/;

    +{ results => tuwf->dbAlli(
        'SELECT COALESCE(iid::text, btype::text) AS id, btype, iid, title
           FROM (',
             sql_join('UNION ALL',
                 (map sql('SELECT 10, ', \"$_", '::board_type, NULL::vndbid, NULL'),
                     grep $qs eq $_ || $BOARD_TYPE{$_}{txt} =~ /\Q$qs/i,
                     grep !$BOARD_TYPE{$_}{dbitem} && ($BOARD_TYPE{$_}{post_perm} eq 'board' || auth->permBoardmod),
                     keys %BOARD_TYPE),
                 sql('SELECT score, \'v\', v.id, title[1+1] FROM', vnt, 'v', $q->sql_join('v', 'v.id'), 'WHERE NOT v.hidden'),
                 sql('SELECT score, \'p\', p.id, title[1+1] FROM', producerst, 'p', $q->sql_join('p', 'p.id'), 'WHERE NOT p.hidden'),
                 sql('SELECT', $uscore, ', \'u\', id, username FROM users WHERE lower(username) LIKE', \lc "%$qs%",
                    $qs =~ /^u$RE{num}$/ ? ('OR id =', \$qs) : ())
             ), ') x(score, btype, iid, title)
           ORDER BY score DESC, btype, title
           LIMIT ', \25
    )}
};

1;
