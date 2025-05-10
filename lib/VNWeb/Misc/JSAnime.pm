package VNWeb::Misc::JSAnime;

use VNWeb::Prelude;

js_api Anime => { search => {}, ref => { anybool => 1 } }, sub($d,@) {
    my $q = $d->{search};
    my $qs = sql_like $q;

    +{ results => fu->SQL(
        'SELECT a.id, a.title_romaji, a.title_kanji
           FROM (',
			INTERSPERSE('UNION ALL',
                $q =~ /^a([0-9]+)$/ ? SQL('SELECT 1, id FROM anime WHERE id =', $1) : (),
                SQL('SELECT  1+substr_score(lower(title_romaji),', $qs, '), id FROM anime WHERE title_romaji ILIKE', "%$qs%"),
                SQL('SELECT 10+substr_score(lower(title_kanji),',  $qs, '), id FROM anime WHERE title_kanji  ILIKE', "%$qs%"),
            ), ') x(prio, id)
           JOIN anime a ON a.id = x.id',
           $d->{ref} ? 'WHERE EXISTS(SELECT 1 FROM vn_anime va WHERE va.aid = a.id)' : (), '
          GROUP BY a.id, a.title_romaji, a.title_kanji
          ORDER BY MIN(x.prio), a.title_romaji
          LIMIT 15'
    )->allh};
};

1;
