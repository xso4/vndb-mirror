package VNWeb::Misc::ElmAnime;

use VNWeb::Prelude;

elm_api Anime => undef, { search => {}, ref => { anybool => 1 } }, sub {
    my($d) = @_;
    my $q = $d->{search};
    my $qs = sql_like $q;

    elm_AnimeResult tuwf->dbPagei({ results => 15, page => 1 },
        'SELECT a.id, a.title_romaji AS title, coalesce(a.title_kanji, \'\') AS original
           FROM (',
			sql_join('UNION ALL',
                $q =~ /^a([0-9]+)$/ ? sql('SELECT 1, id FROM anime WHERE id =', \"$1") : (),
                sql('SELECT  1+substr_score(lower(title_romaji),', \$qs, '), id FROM anime WHERE title_romaji ILIKE', \"%$qs%"),
                sql('SELECT 10+substr_score(lower(title_kanji),',  \$qs, '), id FROM anime WHERE title_kanji  ILIKE', \"%$qs%"),
            ), ') x(prio, id)
           JOIN anime a ON a.id = x.id',
           $d->{ref} ? 'WHERE EXISTS(SELECT 1 FROM vn_anime va WHERE va.aid = a.id)' : (), '
          GROUP BY a.id, a.title_romaji, a.title_kanji
          ORDER BY MIN(x.prio), a.title_romaji
    ');
};

1;
