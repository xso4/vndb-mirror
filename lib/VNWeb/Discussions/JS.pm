package VNWeb::Discussions::JS;

use VNWeb::Prelude;

# Autocompletion search results for boards
js_api Boards => {search => { searchquery => 1 }}, sub {
    fu->denied if !auth->permBoard;
    my $q = shift->{search};
    my $qs = sql_like "$q";

    my $uscore = SQL 'similarity(username, ', $qs, ')';
    $uscore = SQL 'CASE WHEN id =', $qs, 'THEN 2 ELSE', $uscore, 'END' if $qs =~ /^u$RE{num}$/;

    +{ results => fu->SQL(
        'SELECT COALESCE(iid::text, btype::text) AS id, btype, iid, title
           FROM (', INTERSPERSE('UNION ALL',
                 (map SQL('SELECT 10, ', $_, '::board_type, NULL::vndbid, NULL'),
                     grep $qs eq $_ || $BOARD_TYPE{$_}{txt} =~ /\Q$qs/i,
                     grep !$BOARD_TYPE{$_}{dbitem} && ($BOARD_TYPE{$_}{post_perm} eq 'board' || auth->permBoardmod),
                     keys %BOARD_TYPE),
                 SQL('SELECT score, \'v\', v.id, title[2] FROM', VNT, 'v', $q->JOIN('v', 'v.id'), 'WHERE NOT v.hidden'),
                 SQL('SELECT score, \'p\', p.id, title[2] FROM', PRODUCERST, 'p', $q->JOIN('p', 'p.id'), 'WHERE NOT p.hidden'),
                 SQL('SELECT', $uscore, ', \'u\', id, username FROM users WHERE lower(username) LIKE', lc "%$qs%",
                    $qs =~ /^u$RE{num}$/ ? ('OR id =', $qs) : ())
             ), ') x(score, btype, iid, title)
           ORDER BY score DESC, btype, title
           LIMIT 25'
    )->allh}
};

1;
