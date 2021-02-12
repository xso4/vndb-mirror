package VNWeb::Discussions::Elm;

use VNWeb::Prelude;
use VNWeb::Discussions::Lib;

# Autocompletion search results for boards
elm_api Boards => undef, {
    search => {},
}, sub {
    return elm_Unauth if !auth->permBoard;
    my $q = shift->{search};
    my $qs = sql_like $q;

    my sub subq {
        my($prio, $where) = @_;
        sql 'SELECT', $prio, ' AS prio, btype, iid, CASE WHEN iid IS NULL THEN NULL ELSE title END AS title
           FROM (',
              sql_join('UNION ALL',
                sql('SELECT btype, iid, title, original FROM', sql_boards(), 'a'),
                map sql('SELECT', \$_, '::board_type, NULL,', \$BOARD_TYPE{$_}{txt}, q{, ''}),
                grep !$BOARD_TYPE{$_}{dbitem} && ($BOARD_TYPE{$_}{post_perm} eq 'board' || auth->permBoardmod),
                keys %BOARD_TYPE
              ),
           ') x WHERE', $where
    }

    # This query is SLOW :(
    elm_BoardResult tuwf->dbPagei({ results => 10, page => 1 },
        'SELECT btype, iid, title
           FROM (',
             sql_join('UNION ALL',
                 # ID match
                 $q =~ /^($BOARD_RE)$/ && $q =~ /^(([a-z]+)[0-9]*)$/
                    ? subq(0, sql_and sql('btype =', \"$2"), $1 ne $2 ? sql('iid =', \"$1") : ()) : (),
                 subq(
                     sql('1+LEAST(substr_score(lower(title),', \$qs, '), substr_score(lower(original),', \$qs, '))'),
                     sql('title ILIKE', \"%$qs%", ' OR original ILIKE', \"%$qs%")
                 )
             ), ') x
           GROUP BY btype, iid, title
           ORDER BY MIN(prio), btype, iid'
    )
};

1;
