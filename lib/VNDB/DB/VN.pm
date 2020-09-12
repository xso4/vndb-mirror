
package VNDB::DB::VN;

use strict;
use warnings;
use v5.10;
use TUWF 'sqlprint';
use POSIX 'strftime';
use Exporter 'import';
use VNDB::Func 'normalize_query', 'gtintype';

our @EXPORT = qw|dbVNGet dbVNGetRev|;


# Options: id, char, search, gtin, length, lang, olang, plat, tag_inc, tag_exc, tagspoil,
#   hasani, hasshot, ul_notblack, ul_onwish, results, page, what, sort,
#   reverse, inc_hidden, date_before, date_after, released, release, character
# What: extended anime staff seiyuu relations rating ranking vnlist
#  Note: vnlist is ignored (no db search) unless a user is logged in
# Sort: id rel pop rating title tagscore rand
sub dbVNGet {
  my($self, %o) = @_;
  $o{results} ||= 10;
  $o{page}    ||= 1;
  $o{what}    ||= '';
  $o{sort}    ||= 'title';
  $o{tagspoil} //= 2;

  # user input that is literally added to the query should be checked...
  die "Invalid input for tagspoil or tag_inc at dbVNGet()\n" if
    grep !defined($_) || $_!~/^\d+$/, $o{tagspoil},
      !$o{tag_inc} ? () : (ref($o{tag_inc}) ? @{$o{tag_inc}} : $o{tag_inc});

  my $uid = $self->authInfo->{id};

  $o{gtin} = delete $o{search} if $o{search} && $o{search} =~ /^\d+$/ && gtintype(local $_ = $o{search});

  my @where = (
    $o{id} ? (
      'v.id IN(!l)' => [ ref $o{id} ? $o{id} : [$o{id}] ] ) : (),
    $o{char} ? (
      'LOWER(SUBSTR(v.title, 1, 1)) = ?' => $o{char} ) : (),
    defined $o{char} && !$o{char} ? (
      '(ASCII(v.title) < 97 OR ASCII(v.title) > 122) AND (ASCII(v.title) < 65 OR ASCII(v.title) > 90)' => 1 ) : (),
    defined $o{length} ? (
      'v.length IN(!l)' => [ ref $o{length} ? $o{length} : [$o{length}] ]) : (),
    $o{lang} ? (
      'v.c_languages && ARRAY[!l]::language[]' => [ ref $o{lang} ? $o{lang} : [$o{lang}] ]) : (),
    $o{olang} ? (
      'v.c_olang && ARRAY[!l]::language[]' => [ ref $o{olang} ? $o{olang} : [$o{olang}] ]) : (),
    $o{plat} ? (
      'v.c_platforms && ARRAY[!l]::platform[]' => [ ref $o{plat} ? $o{plat} : [$o{plat}] ]) : (),
    defined $o{hasani} ? (
      '!sEXISTS(SELECT 1 FROM vn_anime va WHERE va.id = v.id)' => [ $o{hasani} ? '' : 'NOT ' ]) : (),
    defined $o{hasshot} ? (
      '!sEXISTS(SELECT 1 FROM vn_screenshots vs WHERE vs.id = v.id)' => [ $o{hasshot} ? '' : 'NOT ' ]) : (),
    $o{tag_inc} ? (
      'v.id IN(SELECT vid FROM tags_vn_inherit WHERE tag IN(!l) AND spoiler <= ? GROUP BY vid HAVING COUNT(tag) = ?)',
      [ ref $o{tag_inc} ? $o{tag_inc} : [$o{tag_inc}], $o{tagspoil}, ref $o{tag_inc} ? $#{$o{tag_inc}}+1 : 1 ]) : (),
    $o{tag_exc} ? (
      'v.id NOT IN(SELECT vid FROM tags_vn_inherit WHERE tag IN(!l))' => [ ref $o{tag_exc} ? $o{tag_exc} : [$o{tag_exc}] ] ) : (),
    $o{search} ? (
      map +('v.c_search like ?', "%$_%"), normalize_query($o{search})) : (),
    $o{gtin} ? (
      'v.id IN(SELECT irv.vid FROM releases_vn irv JOIN releases ir ON ir.id = irv.id WHERE ir.gtin = ?)' => $o{gtin}) : (),
    $o{staff_inc} ? ( 'v.id IN(SELECT ivs.id FROM vn_staff ivs JOIN staff_alias isa ON isa.aid = ivs.aid WHERE isa.id IN(!l))' => [ ref $o{staff_inc} ? $o{staff_inc} : [$o{staff_inc}] ] ) : (),
    $o{staff_exc} ? ( 'v.id NOT IN(SELECT ivs.id FROM vn_staff ivs JOIN staff_alias isa ON isa.aid = ivs.aid WHERE isa.id IN(!l))' => [ ref $o{staff_exc} ? $o{staff_exc} : [$o{staff_exc}] ] ) : (),
    $uid && $o{ul_notblack} ? (
      'v.id NOT IN(SELECT vid FROM ulist_vns_labels WHERE uid = ? AND lbl = 6)' => $uid ) : (),
    $uid && defined $o{ul_onwish} ? (
      'v.id !s IN(SELECT vid FROM ulist_vns_labels WHERE uid = ? AND lbl = 5)' => [ $o{ul_onwish} ? '' : 'NOT', $uid ] ) : (),
    $uid && defined $o{ul_voted} ? (
      'v.id !s IN(SELECT vid FROM ulist_vns_labels WHERE uid = ? AND lbl = 7)' => [ $o{ul_voted} ? '' : 'NOT', $uid ] ) : (),
    $uid && defined $o{ul_onlist} ? (
      'v.id !s IN(SELECT vid FROM ulist_vns WHERE uid = ?)' => [ $o{ul_onlist} ? '' : 'NOT', $uid ] ) : (),
    !$o{id} && !$o{inc_hidden} ? (
      'v.hidden = FALSE' => 0 ) : (),
    # optimize fetching random entries (only when there are no other filters present, otherwise this won't work well)
    $o{sort} eq 'rand' && $o{results} <= 10 && !grep(!/^(?:results|page|what|sort|tagspoil)$/, keys %o) ? (
      'v.id IN(SELECT floor(random() * last_value)::integer FROM generate_series(1,20), (SELECT MAX(id) AS last_value FROM vn) s1 LIMIT 20)' ) : (),
    defined $o{date_before} ? ( 'v.c_released <= ?'  => $o{date_before} ) : (),
    defined $o{date_after}  ? ( 'v.c_released >= ?'  => $o{date_after} ) : (),
    defined $o{released}    ? ( 'v.c_released !s ?'  => [ $o{released} ? '<=' : '>', strftime('%Y%m%d', gmtime) ] ) : (),
  );

  if($o{release}) {
    my($q, @p) = sqlprint
      'v.id IN(SELECT rv.vid FROM releases r JOIN releases_vn rv ON rv.id = r.id !W)',
      [ 'NOT r.hidden' => 1, $self->dbReleaseFilters(%{$o{release}}), ];
    push @where, $q, \@p;
  }
  if($o{character}) {
    my($q, @p) = sqlprint
      'v.id IN(SELECT cv.vid FROM chars c JOIN chars_vns cv ON cv.id = c.id !W)',
      [ 'NOT c.hidden' => 1, $self->dbCharFilters(%{$o{character}}) ];
    push @where, $q, \@p;
  }

  my @join = (
    $uid && $o{what} =~ /vnlist/ ? ("LEFT JOIN (
       SELECT irv.vid, COUNT(*) AS userlist_all,
              SUM(CASE WHEN irl.status = 2 THEN 1 ELSE 0 END) AS userlist_obtained
         FROM rlists irl
         JOIN releases_vn irv ON irv.id = irl.rid
        WHERE irl.uid = $uid
        GROUP BY irv.vid
     ) AS vnlist ON vnlist.vid = v.id") : (),
  );

  my $tag_ids = $o{tag_inc} && join ',', ref $o{tag_inc} ? @{$o{tag_inc}} : $o{tag_inc};
  my @select = ( # see https://rt.cpan.org/Ticket/Display.html?id=54224 for the cast on c_languages and c_platforms
    qw|v.id v.locked v.hidden v.c_released v.c_languages::text[] v.c_olang::text[] v.c_platforms::text[] v.title v.original|,
    $o{what} =~ /extended/ ? (
      qw|v.alias v.length v.desc v.l_wp v.l_encubed v.l_renai v.l_wikidata|, 'coalesce(vndbid_num(v.image),0) as image' ) : (),
    $o{what} =~ /rating/ ? (qw|v.c_popularity v.c_rating v.c_votecount|) : (),
    $o{what} =~ /ranking/ ? (
      '(SELECT COUNT(*)+1 FROM vn iv WHERE iv.hidden = false AND iv.c_popularity > COALESCE(v.c_popularity, 0.0)) AS p_ranking',
      '(SELECT COUNT(*)+1 FROM vn iv WHERE iv.hidden = false AND iv.c_rating > COALESCE(v.c_rating, 0.0)) AS r_ranking',
    ) : (),
    $uid && $o{what} =~ /vnlist/ ? (qw|vnlist.userlist_all vnlist.userlist_obtained|) : (),
    # TODO: optimize this, as it will be very slow when the selected tags match a lot of VNs (>1000)
    $tag_ids ?
      qq|(SELECT AVG(tvh.rating) FROM tags_vn_inherit tvh WHERE tvh.tag IN($tag_ids) AND tvh.vid = v.id AND spoiler <= $o{tagspoil} GROUP BY tvh.vid) AS tagscore| : (),
  );

  no if $] >= 5.022, warnings => 'redundant';
  my $order = sprintf {
    id       => 'v.id %s',
    rel      => 'v.c_released %s, v.title ASC',
    pop      => 'v.c_popularity %s NULLS LAST',
    rating   => 'v.c_rating %s NULLS LAST',
    title    => 'v.title %s',
    tagscore => 'tagscore %s, v.title ASC',
    rand     => 'RANDOM()',
  }->{$o{sort}}, $o{reverse} ? 'DESC' : 'ASC';

  my($r, $np) = $self->dbPage(\%o, q|
    SELECT !s
      FROM vn v
      !s
      !W
      ORDER BY !s|,
    join(', ', @select), join(' ', @join), \@where, $order,
  );

  return _enrich($self, $r, $np, 0, $o{what});
}


sub dbVNGetRev {
  my $self = shift;
  my %o = (what => '', @_);

  $o{rev} ||= $self->dbRow('SELECT MAX(rev) AS rev FROM changes WHERE type = \'v\' AND itemid = ?', $o{id})->{rev};

  # XXX: Too much duplication with code in dbVNGet() here. Can we combine some code here?
  my $uid = $self->authInfo->{id};

  my $select = 'c.itemid AS id, vo.c_released, vo.c_languages::text[], vo.c_olang::text[], vo.c_platforms::text[], v.title, v.original';
  $select .= ', extract(\'epoch\' from c.added) as added, c.comments, c.rev, c.ihid, c.ilock, '.VNWeb::DB::sql_user();
  $select .= ', c.id AS cid, NOT EXISTS(SELECT 1 FROM changes c2 WHERE c2.type = c.type AND c2.itemid = c.itemid AND c2.rev = c.rev+1) AS lastrev';
  $select .= ', v.alias, coalesce(vndbid_num(v.image), 0) as image, v.length, v.desc, v.l_wp, v.l_encubed, v.l_renai, v.l_wikidata, vo.hidden, vo.locked' if $o{what} =~ /extended/;
  $select .= ', vo.c_popularity, vo.c_rating, vo.c_votecount' if $o{what} =~ /rating/;
  $select .= ', (SELECT COUNT(*)+1 FROM vn iv WHERE iv.hidden = false AND iv.c_popularity > COALESCE(vo.c_popularity, 0.0)) AS p_ranking'
            .', (SELECT COUNT(*)+1 FROM vn iv WHERE iv.hidden = false AND iv.c_rating > COALESCE(vo.c_rating, 0.0)) AS r_ranking' if $o{what} =~ /ranking/;

  my $r = $self->dbAll(q|
    SELECT !s
      FROM changes c
      JOIN vn vo ON vo.id = c.itemid
      JOIN vn_hist v ON v.chid = c.id
      JOIN users u ON u.id = c.requester
      WHERE c.type = 'v' AND c.itemid = ? AND c.rev = ?|,
    $select, $o{id}, $o{rev}
  );

  return _enrich($self, $r, 0, 1, $o{what});
}


sub _enrich {
  my($self, $r, $np, $rev, $what) = @_;

  if(@$r && $what =~ /anime|relations|staff|seiyuu/) {
    my($col, $hist, $colname) = $rev ? ('cid', '_hist', 'chid') : ('id', '', 'id');
    my %r = map {
      $r->[$_]{anime} = [];
      $r->[$_]{credits} = [];
      $r->[$_]{seiyuu} = [];
      $r->[$_]{relations} = [];
      ($r->[$_]{$col}, $_)
    } 0..$#$r;

    if($what =~ /staff/) {
      push(@{$r->[$r{ delete $_->{xid} }]{credits}}, $_) for (@{$self->dbAll("
        SELECT vs.$colname AS xid, s.id, vs.aid, sa.name, sa.original, s.gender, s.lang, vs.role, vs.note
          FROM vn_staff$hist vs
          JOIN staff_alias sa ON vs.aid = sa.aid
          JOIN staff s ON s.id = sa.id
          WHERE vs.$colname IN(!l)
          ORDER BY vs.role ASC, sa.name ASC",
        [ keys %r ]
      )});
    }

    if($what =~ /seiyuu/) {
      # The seiyuu query needs the VN id to get the VN<->Char spoiler level.
      # Obtaining this ID is different when using the hist table.
      my($vid, $join) = $rev ? ('h.itemid', 'JOIN changes h ON h.id = vs.chid') : ('vs.id', '');
      push(@{$r->[$r{ delete $_->{xid} }]{seiyuu}}, $_) for (@{$self->dbAll("
        SELECT vs.$colname AS xid, s.id, vs.aid, sa.name, sa.original, s.gender, s.lang, c.id AS cid, c.name AS cname, vs.note,
            (SELECT MAX(spoil) FROM chars_vns cv WHERE cv.vid = $vid AND cv.id = c.id) AS spoil
          FROM vn_seiyuu$hist vs
          JOIN staff_alias sa ON vs.aid = sa.aid
          JOIN staff s ON s.id = sa.id
          JOIN chars c ON c.id = vs.cid
          $join
          WHERE vs.$colname IN(!l)
          ORDER BY c.name",
        [ keys %r ]
      )});
    }

    if($what =~ /anime/) {
      push(@{$r->[$r{ delete $_->{xid} }]{anime}}, $_) for (@{$self->dbAll("
        SELECT va.$colname AS xid, a.id, a.year, a.ann_id, a.nfo_id, a.type, a.title_romaji, a.title_kanji, extract('epoch' from a.lastfetch) AS lastfetch
          FROM vn_anime$hist va
          JOIN anime a ON va.aid = a.id
          WHERE va.$colname IN(!l)",
        [ keys %r ]
      )});
    }

    if($what =~ /relations/) {
      push(@{$r->[$r{ delete $_->{xid} }]{relations}}, $_) for(@{$self->dbAll("
        SELECT rel.$colname AS xid, rel.vid AS id, rel.relation, rel.official, v.title, v.original
          FROM vn_relations$hist rel
          JOIN vn v ON rel.vid = v.id
          WHERE rel.$colname IN(!l)",
        [ keys %r ]
      )});
    }
  }

  VNWeb::DB::enrich_flatten(vnlist_labels => id => vid => sub { VNWeb::DB::sql('
    SELECT uvl.vid, ul.label
      FROM ulist_vns_labels uvl
      JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl
     WHERE uvl.uid =', \$self->authInfo->{id}, 'AND uvl.vid IN', $_[0], '
    ORDER BY CASE WHEN ul.id < 10 THEN ul.id ELSE 10 END, ul.label'
  )}, $r) if $what =~ /vnlist/ && $self->authInfo->{id};

  return wantarray ? ($r, $np) : $r;
}


1;
