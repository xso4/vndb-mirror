-- A small note on the function naming scheme:
--   edit_*      -> revision insertion abstraction functions
--   *_notify    -> functions issuing a PgSQL NOTIFY statement
--   notify_*    -> functions creating entries in the notifications table
--   user_*      -> functions to manage users and sessions
--   update_*    -> functions to update a cache
--   *_calc      ^  (same, should prolly rename to the update_* scheme for consistency)
-- I like to keep the nouns in functions singular, in contrast to the table
-- naming scheme where nouns are always plural. But I'm not very consistent
-- with that, either.


-- Handy function to format an ipinfo type for human consumption.
CREATE OR REPLACE FUNCTION fmtip(n ipinfo) RETURNS text AS $$
  SELECT COALESCE(COALESCE((n).country, 'X')||':'||(n).asn||COALESCE(':'||(n).as_name,'')||'/', (n).country||'/', '')
      || abbrev((n).ip)
      || CASE WHEN (n).anonymous_proxy    THEN ' ANON' ELSE '' END
      || CASE WHEN (n).sattelite_provider THEN ' SAT'  ELSE '' END
      || CASE WHEN (n).anycast            THEN ' ANY'  ELSE '' END
      || CASE WHEN (n).drop               THEN ' DROP' ELSE '' END
$$ LANGUAGE SQL IMMUTABLE;



-- Helper function for `update_search()`
CREATE OR REPLACE FUNCTION update_search_terms(objid vndbid) RETURNS SETOF record AS $$
DECLARE
  e int; -- because I'm too lazy to write out 'NULL::int' every time.
BEGIN
  CASE vndbid_type(objid)
  WHEN 'v' THEN RETURN QUERY
              SELECT e, 3, search_norm_term(title) FROM vn_titles WHERE id = objid
    UNION ALL SELECT e, 3, search_norm_term(latin) FROM vn_titles WHERE id = objid
    UNION ALL SELECT e, 2, search_norm_term(a) FROM vn, regexp_split_to_table(alias, E'\n') a(a) WHERE objid = id
    -- Remove the various editions/version strings from release titles,
    -- this reduces the index size and makes VN search more relevant.
    -- People looking for editions should be using the release search.
    UNION ALL SELECT e, 1, regexp_replace(search_norm_term(t), '(?:
         体験|ダウンロド|初回限定|初回|限定|通常|廉価|豪華|追加|コレクション
        |パッケージ|ダウンロード|ベスト|復刻|新装|7対応|版|生産|リメイク
        |first|press|limited|regular|standard|full|remake
        |pack|package|boxed|download|complete|popular|premium|deluxe|collectors?|collection
        |lowprice|price|free|best|thebest|cheap|budget|reprint|bundle|set|renewal|extended
        |special|trial|demo|allages|voiced?|uncensored|web|patch|port|r18|18|earlyaccess
        |cd|cdr|cdrom|dvdrom|dvd|dvdpg|disk|disc|steam|for
        |(?:win|windows)(?:7|10|95)?|vista|pc9821|support(?:ed)?
        |(?:parts?|vol|volumes?|chapters?|v|ver|versions?)(?:[0-9]+)
        |editions?|version|production|thebest|append|scenario|dlc)+$', '', 'xg')
      FROM (
        SELECT title FROM releases r JOIN releases_vn rv ON rv.id = r.id JOIN releases_titles rt ON rt.id = r.id WHERE NOT r.hidden AND rv.vid = objid
        UNION ALL
        SELECT latin FROM releases r JOIN releases_vn rv ON rv.id = r.id JOIN releases_titles rt ON rt.id = r.id WHERE NOT r.hidden AND rv.vid = objid
      ) r(t);

  WHEN 'r' THEN RETURN QUERY
              SELECT e, 3, search_norm_term(title) FROM releases_titles WHERE id = objid
    UNION ALL SELECT e, 3, search_norm_term(latin) FROM releases_titles WHERE id = objid
    UNION ALL SELECT e, 1, gtin::text FROM releases WHERE id = objid AND gtin <> 0
    UNION ALL SELECT e, 1, search_norm_term(catalog) FROM releases WHERE id = objid AND catalog <> '';

  WHEN 'c' THEN RETURN QUERY
              SELECT e, 3, search_norm_term(name)  FROM chars WHERE id = objid
    UNION ALL SELECT e, 3, search_norm_term(latin) FROM chars WHERE id = objid
    UNION ALL SELECT e, 2, search_norm_term(a) FROM chars, regexp_split_to_table(alias, E'\n') a(a) WHERE id = objid;

  WHEN 'p' THEN RETURN QUERY
              SELECT e, 3, search_norm_term(name)  FROM producers WHERE id = objid
    UNION ALL SELECT e, 3, search_norm_term(latin) FROM producers WHERE id = objid
    UNION ALL SELECT e, 2, search_norm_term(a) FROM producers, regexp_split_to_table(alias, E'\n') a(a) WHERE id = objid;

  WHEN 's' THEN RETURN QUERY
              SELECT aid, 3, search_norm_term(name)  FROM staff_alias WHERE id = objid
    UNION ALL SELECT aid, 3, search_norm_term(latin) FROM staff_alias WHERE id = objid;

  WHEN 'g' THEN RETURN QUERY
              SELECT e, 3, search_norm_term(name) FROM tags WHERE id = objid
    UNION ALL SELECT e, 2, search_norm_term(a)    FROM tags, regexp_split_to_table(alias, E'\n') a(a) WHERE objid = id;

  WHEN 'i' THEN RETURN QUERY
              SELECT e, 3, search_norm_term(name) FROM traits WHERE id = objid
    UNION ALL SELECT e, 2, search_norm_term(a)    FROM traits, regexp_split_to_table(alias, E'\n') a(a) WHERE objid = id;

  ELSE RAISE 'unknown objid type';
  END CASE;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION update_search(objid vndbid) RETURNS void AS $$
  WITH excluded(excluded) AS (
    -- VN, tag & trait search needs to support finding 'hidden' items, but for
    -- other entry types we can safely exclude those from the search cache.
    SELECT 1
     WHERE (vndbid_type(objid) = 'r' AND EXISTS(SELECT 1 FROM releases  WHERE hidden AND id = objid))
        OR (vndbid_type(objid) = 'c' AND EXISTS(SELECT 1 FROM chars     WHERE hidden AND id = objid))
        OR (vndbid_type(objid) = 'p' AND EXISTS(SELECT 1 FROM producers WHERE hidden AND id = objid))
        OR (vndbid_type(objid) = 's' AND EXISTS(SELECT 1 FROM staff     WHERE hidden AND id = objid))
  ), uniq(subid, prio, label) AS (
    SELECT subid, MAX(prio)::smallint, label
      FROM update_search_terms(objid) x (subid int, prio int, label text)
     WHERE label IS NOT NULL AND label <> '' AND NOT EXISTS(SELECT 1 FROM excluded)
     GROUP BY subid, label
  ), terms(subid, prio, label) AS (
    -- It's possible for some entries to have no searchable terms at all, e.g.
    -- when their titles only consists of characters that are normalized away.
    -- In that case we still need to have at least one row in the search_cache
    -- table for the id-based search to work.  (Would be nicer to support
    -- non-normalized search in those cases, but these cases aren't too common)
    SELECT * FROM uniq
    UNION ALL
    SELECT NULL::int, 1, '' WHERE NOT EXISTS(SELECT 1 FROM excluded) AND NOT EXISTS(SELECT 1 FROM uniq)
  ), n(subid, prio, label) AS (
     SELECT COALESCE(t.subid, o.subid), t.prio, COALESCE(t.label, o.label)
       FROM terms t
       FULL OUTER JOIN (SELECT subid, label FROM search_cache WHERE id = objid) o ON o.subid IS NOT DISTINCT FROM t.subid AND o.label = t.label
  ) MERGE INTO search_cache o USING n ON o.id = objid AND (o.subid, o.label) IS NOT DISTINCT FROM (n.subid, n.label)
      WHEN NOT MATCHED THEN INSERT (id, subid, prio, label) VALUES (objid, subid, n.prio, n.label)
      WHEN MATCHED AND n.prio IS NULL THEN DELETE
      WHEN MATCHED AND n.prio <> o.prio THEN UPDATE SET prio = n.prio;
$$ LANGUAGE SQL;



-- Helper function for the titleprefs functions below.
CREATE OR REPLACE FUNCTION titleprefs_swap(p titleprefs, lang language, title text, latin text) RETURNS text[] AS $$
  SELECT ARRAY[lang::text, CASE WHEN (
            CASE WHEN p.t1_lang = lang THEN p.t1_latin
                 WHEN p.t2_lang = lang THEN p.t2_latin
                 WHEN p.t3_lang = lang THEN p.t3_latin
                 WHEN p.t4_lang = lang THEN p.t4_latin ELSE p IS NULL OR p.to_latin END
         ) THEN COALESCE(latin, title) ELSE title END, lang::text, CASE WHEN (
            CASE WHEN p.a1_lang = lang THEN p.a1_latin
                 WHEN p.a2_lang = lang THEN p.a2_latin
                 WHEN p.a3_lang = lang THEN p.a3_latin
                 WHEN p.a4_lang = lang THEN p.a4_latin ELSE p.ao_latin END
         ) THEN COALESCE(latin, title) ELSE title END]
$$ LANGUAGE SQL STABLE;


-- This is a pure-SQL implementation of the title preference selection
-- algorithm in VNWeb::TitlePrefs. Given a preferences object, this function
-- returns a copy of the 'vn' table with two additional columns:
-- * title      - Array of: main title language, main title, secondary title language, secondary title
-- * sorttitle  - title to be used in ORDER BY clause
--
-- The 'title' array format is (supposed to be) used pervasively through the
-- back-end code to order to easily pass around titles as a single object and
-- to support proper rendering of both the main & secondary title of each
-- entry.
--
-- This function looks slow and messy, but it's been specifically written to be
-- transparent to the query planner and so that unused joins can be fully
-- optimized out during query execution. Even with that, it's better to avoid
-- this function in complex queries when possible because you may run into
-- bad query plans by hitting join_collapse_limit or from_collapse_limit.
-- (More info at https://dev.yorhel.nl/doc/vndbtitles)
CREATE OR REPLACE FUNCTION vnt(p titleprefs) RETURNS SETOF vnt AS $$
  -- The language selection logic below is specially written so that the planner can remove references to joined tables corresponding to NULL languages.
  SELECT v.*, (CASE
      WHEN p.t1_lang = t1.lang AND (NOT p.t1_official OR t1.official) AND (p.t1_official IS NOT NULL OR p.t1_lang = v.olang) THEN ARRAY[t1.lang::text, COALESCE(CASE WHEN p.t1_latin THEN t1.latin ELSE NULL END, t1.title)] 
      WHEN p.t2_lang = t2.lang AND (NOT p.t2_official OR t2.official) AND (p.t2_official IS NOT NULL OR p.t2_lang = v.olang) THEN ARRAY[t2.lang::text, COALESCE(CASE WHEN p.t2_latin THEN t2.latin ELSE NULL END, t2.title)]
      WHEN p.t3_lang = t3.lang AND (NOT p.t3_official OR t3.official) AND (p.t3_official IS NOT NULL OR p.t3_lang = v.olang) THEN ARRAY[t3.lang::text, COALESCE(CASE WHEN p.t3_latin THEN t3.latin ELSE NULL END, t3.title)]
      WHEN p.t4_lang = t4.lang AND (NOT p.t4_official OR t4.official) AND (p.t4_official IS NOT NULL OR p.t4_lang = v.olang) THEN ARRAY[t4.lang::text, COALESCE(CASE WHEN p.t4_latin THEN t4.latin ELSE NULL END, t4.title)]
      ELSE ARRAY[v.olang::text, COALESCE(CASE WHEN p IS NULL OR p.to_latin THEN ol.latin ELSE NULL END, ol.title)] END
      ) || (CASE
      WHEN p.a1_lang = a1.lang AND (NOT p.a1_official OR a1.official) AND (p.a1_official IS NOT NULL OR p.a1_lang = v.olang) THEN ARRAY[a1.lang::text, COALESCE(CASE WHEN p.a1_latin THEN a1.latin ELSE NULL END, a1.title)] 
      WHEN p.a2_lang = a2.lang AND (NOT p.a2_official OR a2.official) AND (p.a2_official IS NOT NULL OR p.a2_lang = v.olang) THEN ARRAY[a2.lang::text, COALESCE(CASE WHEN p.a2_latin THEN a2.latin ELSE NULL END, a2.title)]
      WHEN p.a3_lang = a3.lang AND (NOT p.a3_official OR a3.official) AND (p.a3_official IS NOT NULL OR p.a3_lang = v.olang) THEN ARRAY[a3.lang::text, COALESCE(CASE WHEN p.a3_latin THEN a3.latin ELSE NULL END, a3.title)]
      WHEN p.a4_lang = a4.lang AND (NOT p.a4_official OR a4.official) AND (p.a4_official IS NOT NULL OR p.a4_lang = v.olang) THEN ARRAY[a4.lang::text, COALESCE(CASE WHEN p.a4_latin THEN a4.latin ELSE NULL END, a4.title)]
      ELSE ARRAY[v.olang::text, COALESCE(CASE WHEN p.ao_latin THEN ol.latin ELSE NULL END, ol.title)] END)
    , CASE
      WHEN p.t1_lang = t1.lang AND (NOT p.t1_official OR t1.official) AND (p.t1_official IS NOT NULL OR p.t1_lang = v.olang) THEN COALESCE(t1.latin, t1.title)
      WHEN p.t2_lang = t2.lang AND (NOT p.t2_official OR t2.official) AND (p.t2_official IS NOT NULL OR p.t2_lang = v.olang) THEN COALESCE(t2.latin, t2.title)
      WHEN p.t3_lang = t3.lang AND (NOT p.t3_official OR t3.official) AND (p.t3_official IS NOT NULL OR p.t3_lang = v.olang) THEN COALESCE(t3.latin, t3.title)
      WHEN p.t4_lang = t4.lang AND (NOT p.t4_official OR t4.official) AND (p.t4_official IS NOT NULL OR p.t4_lang = v.olang) THEN COALESCE(t4.latin, t4.title)
      ELSE COALESCE(ol.latin, ol.title) END
    FROM vn v
    JOIN vn_titles ol ON ol.id = v.id AND ol.lang = v.olang
    -- The COALESCE() below is kind of meaningless, but apparently the query planner can't optimize out JOINs with NULL conditions.
    LEFT JOIN vn_titles t1 ON t1.id = v.id AND t1.lang = COALESCE(p.t1_lang, 'en')
    LEFT JOIN vn_titles t2 ON t2.id = v.id AND t2.lang = COALESCE(p.t2_lang, 'en')
    LEFT JOIN vn_titles t3 ON t3.id = v.id AND t3.lang = COALESCE(p.t3_lang, 'en')
    LEFT JOIN vn_titles t4 ON t4.id = v.id AND t4.lang = COALESCE(p.t4_lang, 'en')
    LEFT JOIN vn_titles a1 ON a1.id = v.id AND a1.lang = COALESCE(p.a1_lang, 'en')
    LEFT JOIN vn_titles a2 ON a2.id = v.id AND a2.lang = COALESCE(p.a2_lang, 'en')
    LEFT JOIN vn_titles a3 ON a3.id = v.id AND a3.lang = COALESCE(p.a3_lang, 'en')
    LEFT JOIN vn_titles a4 ON a4.id = v.id AND a4.lang = COALESCE(p.a4_lang, 'en')
$$ LANGUAGE SQL STABLE;



-- Same thing as vnt()
CREATE OR REPLACE FUNCTION releasest(p titleprefs) RETURNS SETOF releasest AS $$
  SELECT r.*, (CASE
      WHEN p.t1_lang = t1.lang AND (p.t1_official IS NOT NULL OR p.t1_lang = r.olang) THEN ARRAY[t1.lang::text, COALESCE(CASE WHEN p.t1_latin THEN t1.latin ELSE NULL END, t1.title)] 
      WHEN p.t2_lang = t2.lang AND (p.t2_official IS NOT NULL OR p.t2_lang = r.olang) THEN ARRAY[t2.lang::text, COALESCE(CASE WHEN p.t2_latin THEN t2.latin ELSE NULL END, t2.title)]
      WHEN p.t3_lang = t3.lang AND (p.t3_official IS NOT NULL OR p.t3_lang = r.olang) THEN ARRAY[t3.lang::text, COALESCE(CASE WHEN p.t3_latin THEN t3.latin ELSE NULL END, t3.title)]
      WHEN p.t4_lang = t4.lang AND (p.t4_official IS NOT NULL OR p.t4_lang = r.olang) THEN ARRAY[t4.lang::text, COALESCE(CASE WHEN p.t4_latin THEN t4.latin ELSE NULL END, t4.title)]
      ELSE ARRAY[r.olang::text, COALESCE(CASE WHEN p IS NULL OR p.to_latin THEN ol.latin ELSE NULL END, ol.title)] END
      ) || (CASE
      WHEN p.a1_lang = a1.lang AND (p.a1_official IS NOT NULL OR p.a1_lang = r.olang) THEN ARRAY[a1.lang::text, COALESCE(CASE WHEN p.a1_latin THEN a1.latin ELSE NULL END, a1.title)] 
      WHEN p.a2_lang = a2.lang AND (p.a2_official IS NOT NULL OR p.a2_lang = r.olang) THEN ARRAY[a2.lang::text, COALESCE(CASE WHEN p.a2_latin THEN a2.latin ELSE NULL END, a2.title)]
      WHEN p.a3_lang = a3.lang AND (p.a3_official IS NOT NULL OR p.a3_lang = r.olang) THEN ARRAY[a3.lang::text, COALESCE(CASE WHEN p.a3_latin THEN a3.latin ELSE NULL END, a3.title)]
      WHEN p.a4_lang = a4.lang AND (p.a4_official IS NOT NULL OR p.a4_lang = r.olang) THEN ARRAY[a4.lang::text, COALESCE(CASE WHEN p.a4_latin THEN a4.latin ELSE NULL END, a4.title)]
      ELSE ARRAY[r.olang::text, COALESCE(CASE WHEN p.ao_latin THEN ol.latin ELSE NULL END, ol.title)] END)
    , CASE
      WHEN p.t1_lang = t1.lang AND (p.t1_official IS NOT NULL OR p.t1_lang = r.olang) THEN COALESCE(t1.latin, t1.title)
      WHEN p.t2_lang = t2.lang AND (p.t2_official IS NOT NULL OR p.t2_lang = r.olang) THEN COALESCE(t2.latin, t2.title)
      WHEN p.t3_lang = t3.lang AND (p.t3_official IS NOT NULL OR p.t3_lang = r.olang) THEN COALESCE(t3.latin, t3.title)
      WHEN p.t4_lang = t4.lang AND (p.t4_official IS NOT NULL OR p.t4_lang = r.olang) THEN COALESCE(t4.latin, t4.title)
      ELSE COALESCE(ol.latin, ol.title) END
    FROM releases r
    JOIN releases_titles ol ON ol.id = r.id AND ol.lang = r.olang
    LEFT JOIN releases_titles t1 ON t1.id = r.id AND t1.lang = COALESCE(p.t1_lang, 'en') AND t1.title IS NOT NULL
    LEFT JOIN releases_titles t2 ON t2.id = r.id AND t2.lang = COALESCE(p.t2_lang, 'en') AND t2.title IS NOT NULL
    LEFT JOIN releases_titles t3 ON t3.id = r.id AND t3.lang = COALESCE(p.t3_lang, 'en') AND t3.title IS NOT NULL
    LEFT JOIN releases_titles t4 ON t4.id = r.id AND t4.lang = COALESCE(p.t4_lang, 'en') AND t4.title IS NOT NULL
    LEFT JOIN releases_titles a1 ON a1.id = r.id AND a1.lang = COALESCE(p.a1_lang, 'en') AND a1.title IS NOT NULL
    LEFT JOIN releases_titles a2 ON a2.id = r.id AND a2.lang = COALESCE(p.a2_lang, 'en') AND a2.title IS NOT NULL
    LEFT JOIN releases_titles a3 ON a3.id = r.id AND a3.lang = COALESCE(p.a3_lang, 'en') AND a3.title IS NOT NULL
    LEFT JOIN releases_titles a4 ON a4.id = r.id AND a4.lang = COALESCE(p.a4_lang, 'en') AND a4.title IS NOT NULL
$$ LANGUAGE SQL STABLE;



-- This one just flips the name/original columns around depending on
-- preferences, so is fast enough to use directly.
CREATE OR REPLACE FUNCTION producerst(p titleprefs) RETURNS SETOF producerst AS $$
  SELECT *, titleprefs_swap(p, lang, name, latin), COALESCE(latin, name) FROM producers
$$ LANGUAGE SQL STABLE;



-- Same for charst
CREATE OR REPLACE FUNCTION charst(p titleprefs) RETURNS SETOF charst AS $$
  SELECT *, titleprefs_swap(p, c_lang, name, latin), COALESCE(latin, name) FROM chars
$$ LANGUAGE SQL STABLE;



-- Same for staff_aliast
CREATE OR REPLACE FUNCTION staff_aliast(p titleprefs) RETURNS SETOF staff_aliast AS $$
    SELECT s.*, sa.aid, sa.name, sa.latin
         , titleprefs_swap(p, s.lang, sa.name, sa.latin), COALESCE(sa.latin, sa.name)
      FROM staff s
      JOIN staff_alias sa ON sa.id = s.id
$$ LANGUAGE SQL STABLE;



-- update_vncache(id) - updates some c_* columns in the vn table
CREATE OR REPLACE FUNCTION update_vncache(vndbid) RETURNS void AS $$
  UPDATE vn SET
    c_released = COALESCE((
      SELECT MIN(r.released)
        FROM releases r
        JOIN releases_vn rv ON r.id = rv.id
       WHERE rv.vid = $1
         AND rv.rtype <> 'trial'
         AND r.hidden = FALSE
         AND r.released <> 0
         AND r.official
      GROUP BY rv.vid
    ), 0),
    c_languages = ARRAY(
      SELECT rl.lang
        FROM releases_titles rl
        JOIN releases r ON r.id = rl.id
        JOIN releases_vn rv ON r.id = rv.id
       WHERE rv.vid = $1
         AND rv.rtype <> 'trial'
         AND NOT rl.mtl
         AND r.released <= TO_CHAR('today'::timestamp, 'YYYYMMDD')::integer
         AND r.hidden = FALSE
      GROUP BY rl.lang
      ORDER BY rl.lang
    ),
    c_platforms = ARRAY(
      SELECT rp.platform
        FROM releases_platforms rp
        JOIN releases r ON rp.id = r.id
        JOIN releases_vn rv ON rp.id = rv.id
       WHERE rv.vid = $1
        AND rv.rtype <> 'trial'
        AND r.released <= TO_CHAR('today'::timestamp, 'YYYYMMDD')::integer
        AND r.hidden = FALSE
      GROUP BY rp.platform
      ORDER BY rp.platform
    ),
    c_developers = ARRAY(
      SELECT rp.pid
        FROM releases_producers rp
        JOIN releases r ON rp.id = r.id
        JOIN releases_vn rv ON rv.id = r.id
       WHERE rv.vid = $1
         AND r.official AND rp.developer
         AND r.hidden = FALSE
      GROUP BY rp.pid
      ORDER BY rp.pid
    )
  WHERE id = $1;
$$ LANGUAGE sql;


-- Update c_rating, c_votecount, c_pop_rank, c_rat_rank and c_average
CREATE OR REPLACE FUNCTION update_vnvotestats() RETURNS void AS $$
  WITH votes(vid, uid, vote) AS ( -- List of all non-ignored VN votes
    SELECT vid, uid, vote FROM ulist_vns WHERE vote IS NOT NULL AND uid NOT IN(SELECT id FROM users WHERE ign_votes)
  ), avgavg(avgavg) AS ( -- Average vote average
    SELECT AVG(a)::real FROM (SELECT AVG(vote) FROM votes GROUP BY vid) x(a)
  ), ratings(vid, count, average, rating) AS ( -- Ratings and vote counts
    SELECT vid, COUNT(uid), (AVG(vote)*10)::smallint,
           -- Bayesian average B(a,p,votes) = (p * a + sum(votes)) / (p + count(votes))
           --   p = (1 - min(1, count(votes)/100)) * 7     i.e. linear interpolation from 7 to 0 for vote counts from 0 to 100.
           --   a = Average vote average
           ( (1 - LEAST(1, COUNT(uid)::real/100))*7  *  (SELECT avgavg FROM avgavg)  +  SUM(vote) ) /
           ( (1 - LEAST(1, COUNT(uid)::real/100))*7  +  COUNT(uid) )
      FROM votes
     GROUP BY vid
  ), capped(vid, count, average, rating) AS ( -- Ratings, but capped
     SELECT vid, count, average, CASE
        WHEN count <   5 THEN NULL
        WHEN count <  50 THEN LEAST(rating, (SELECT rating FROM ratings WHERE count >=  50 ORDER BY rating DESC LIMIT 1 OFFSET 101))
        WHEN count < 100 THEN LEAST(rating, (SELECT rating FROM ratings WHERE count >= 100 ORDER BY rating DESC LIMIT 1 OFFSET  51))
        ELSE rating END
       FROM ratings
  ), stats(vid, count, average, rating, rat_rank, pop_rank) AS ( -- Combined stats
    SELECT v.id, COALESCE(r.count, 0), r.average, (r.rating*10)::smallint
         , CASE WHEN r.rating IS NULL THEN NULL ELSE rank() OVER(ORDER BY hidden, r.rating DESC NULLS LAST) END
         , rank() OVER(ORDER BY hidden, r.count DESC NULLS LAST)
      FROM vn v
      LEFT JOIN capped r ON r.vid = v.id
  )
  UPDATE vn SET c_rating = rating, c_votecount = count, c_pop_rank = pop_rank, c_rat_rank = rat_rank, c_average = average
    FROM stats
   WHERE id = vid AND (c_rating, c_votecount, c_pop_rank, c_rat_rank, c_average) IS DISTINCT FROM (rating, count, pop_rank, rat_rank, average);
$$ LANGUAGE SQL;



-- Updates vn.c_length and vn.c_lengthnum
CREATE OR REPLACE FUNCTION update_vn_length_cache(vndbid) RETURNS void AS $$
  WITH s (vid, cnt, len) AS (
    SELECT v.id, count(l.vid) FILTER (WHERE u.id IS NOT NULL AND l.vid IS NOT NULL AND v.devstatus <> 1)
         , percentile_cont(0.5) WITHIN GROUP (ORDER BY l.length + (l.length/4 * (l.speed-1))) FILTER (WHERE u.id IS NOT NULL AND l.vid IS NOT NULL AND v.devstatus <> 1)
      FROM vn v
      LEFT JOIN vn_length_votes l ON l.vid = v.id AND l.speed IS NOT NULL AND NOT l.private
      LEFT JOIN users u ON u.id = l.uid AND u.perm_lengthvote
     WHERE ($1 IS NULL OR v.id = $1)
     GROUP BY v.id
  ) UPDATE vn SET c_lengthnum = cnt, c_length = len
      FROM s
     WHERE s.vid = id AND (c_lengthnum, c_length) IS DISTINCT FROM (cnt, len)
$$ LANGUAGE SQL;



-- c_weight = if not_referenced then 0 else lower(c_votecount) -> higher(c_weight) && higher(*_stddev) -> higher(c_weight)
--
-- Current algorithm:
--
--   votes_weight = 2 ^ max(0, 14 - c_votecount)   -> exponential weight between 1 and 2^13 (~16k)
--   (sexual|violence)_weight = (stddev/max_stddev)^2 * 100
--   weight = votes_weight + sexual_weight + violence_weight
--
-- This isn't very grounded in theory, I've no clue how statistics work. I
-- suspect confidence intervals/levels are more appropriate for this use case.
CREATE OR REPLACE FUNCTION update_images_cache(vndbid) RETURNS void AS $$
BEGIN
  UPDATE images
     SET c_votecount = votecount, c_sexual_avg = sexual_avg, c_sexual_stddev = sexual_stddev
       , c_violence_avg = violence_avg, c_violence_stddev = violence_stddev, c_weight = weight, c_uids = uids
    FROM (
      SELECT s.id, s.votecount, s.uids
           , COALESCE(s.sexual_avg  *100, 200) AS sexual_avg,   COALESCE(s.sexual_stddev  *100, 0) AS sexual_stddev
           , COALESCE(s.violence_avg*100, 200) AS violence_avg, COALESCE(s.violence_stddev*100, 0) AS violence_stddev
           , CASE WHEN s.votecount >= 15 THEN 1 -- Lock the weight at 1 at 15 votes, collecting more votes is just inefficient
             WHEN EXISTS(
                          SELECT 1 FROM vn v                                        WHERE s.id BETWEEN 'cv1' AND vndbid_max('cv') AND NOT v.hidden AND v.image = s.id
                UNION ALL SELECT 1 FROM vn_screenshots vs JOIN vn v ON v.id = vs.id WHERE s.id BETWEEN 'sf1' AND vndbid_max('sf') AND NOT v.hidden AND vs.scr = s.id
                UNION ALL SELECT 1 FROM chars c                                     WHERE s.id BETWEEN 'ch1' AND vndbid_max('ch') AND NOT c.hidden AND c.image = s.id
             )
             THEN ceil(pow(2, greatest(0, 14 - s.votecount)) + coalesce(pow(s.sexual_stddev, 2), 0)*100 + coalesce(pow(s.violence_stddev, 2), 0)*100)
             ELSE 0 END AS weight
        FROM (
            SELECT i.id, count(iv.id) AS votecount
                 , round(avg(sexual)   FILTER(WHERE NOT iv.ignore), 2) AS sexual_avg
                 , round(avg(violence) FILTER(WHERE NOT iv.ignore), 2) AS violence_avg
                 , round(stddev_pop(sexual)   FILTER(WHERE NOT iv.ignore), 2) AS sexual_stddev
                 , round(stddev_pop(violence) FILTER(WHERE NOT iv.ignore), 2) AS violence_stddev
                 , coalesce(array_agg(u.id) FILTER(WHERE u.id IS NOT NULL), '{}') AS uids
              FROM images i
              LEFT JOIN image_votes iv ON iv.id = i.id
              LEFT JOIN users u ON u.id = iv.uid
             WHERE ($1 IS NULL OR i.id = $1)
               AND (u.id IS NULL OR u.perm_imgvote)
             GROUP BY i.id
        ) s
    ) weights
   WHERE weights.id = images.id AND (c_votecount, c_sexual_avg, c_sexual_stddev, c_violence_avg, c_violence_stddev, c_weight, c_uids)
                   IS DISTINCT FROM (votecount,   sexual_avg,   sexual_stddev,   violence_avg,   violence_stddev,   weight,   uids);
END; $$ LANGUAGE plpgsql;



-- Update reviews.c_up, c_down and c_flagged
CREATE OR REPLACE FUNCTION update_reviews_votes_cache(vndbid) RETURNS void AS $$
BEGIN
  WITH stats(id,up,down) AS (
    SELECT r.id
         , COALESCE(SUM(CASE WHEN rv.overrule THEN 100000 WHEN rv.ip IS NULL THEN 100 ELSE 1 END) FILTER(WHERE     rv.vote AND u.ign_votes IS DISTINCT FROM true AND (rv.overrule OR r2.id IS NULL)), 0)
         , COALESCE(SUM(CASE WHEN rv.overrule THEN 100000 WHEN rv.ip IS NULL THEN 100 ELSE 1 END) FILTER(WHERE NOT rv.vote AND u.ign_votes IS DISTINCT FROM true AND (rv.overrule OR r2.id IS NULL)), 0)
      FROM reviews r
      LEFT JOIN reviews_votes rv ON rv.id = r.id
      LEFT JOIN users u ON u.id = rv.uid
      LEFT JOIN reviews r2 ON r2.vid = r.vid AND r2.uid = rv.uid
     WHERE $1 IS NULL OR r.id = $1
     GROUP BY r.id
  )
  UPDATE reviews SET c_up = up, c_down = down, c_flagged = up-down<-10000
    FROM stats WHERE reviews.id = stats.id AND (c_up,c_down,c_flagged) <> (up,down,up-down<10000);
END; $$ LANGUAGE plpgsql;



-- Update users.c_vns, c_votes and c_wish for one user (when given an id) or all users (when given NULL)
CREATE OR REPLACE FUNCTION update_users_ulist_stats(vndbid) RETURNS void AS $$
BEGIN
  WITH cnt(uid, votes, vns, wish) AS (
    SELECT u.id
         , COUNT(uv.vid) FILTER (WHERE NOT uv.c_private AND uv.vote IS NOT NULL) -- Voted
         , COUNT(uv.vid) FILTER (WHERE NOT uv.c_private AND NOT (uv.labels <@ ARRAY[5,6]::smallint[])) -- Labelled, but not wishlish/blacklist
         , COUNT(uv.vid) FILTER (WHERE uwish.private IS NOT DISTINCT FROM false AND uv.labels && ARRAY[5::smallint]) -- Wishlist
      FROM users u
      LEFT JOIN ulist_vns uv ON uv.uid = u.id
      LEFT JOIN ulist_labels uwish ON uwish.uid = u.id AND uwish.id = 5
     WHERE $1 IS NULL OR u.id = $1
     GROUP BY u.id
  ) UPDATE users SET c_votes = votes, c_vns = vns, c_wish = wish
      FROM cnt WHERE id = uid AND (c_votes, c_vns, c_wish) IS DISTINCT FROM (votes, vns, wish);
END;
$$ LANGUAGE plpgsql; -- Don't use "LANGUAGE SQL" here; Make sure to generate a new query plan at invocation time.



-- Update ulist_vns.c_private for a particular (user, vid). vid can be null to
-- update the cache for the all VNs in the user's list, user can also be null
-- to update the cache for everyone.
CREATE OR REPLACE FUNCTION update_users_ulist_private(vndbid, vndbid) RETURNS void AS $$
BEGIN
  WITH p(uid,vid,private) AS (
    SELECT uv.uid, uv.vid, COALESCE(bool_and(l.private), true)
      FROM ulist_vns uv
      LEFT JOIN unnest(uv.labels) x(id) ON true
      LEFT JOIN ulist_labels l ON l.id = x.id AND l.uid = uv.uid
     WHERE ($1 IS NULL OR uv.uid = $1)
       AND ($2 IS NULL OR uv.vid = $2)
     GROUP BY uv.uid, uv.vid
  ) UPDATE ulist_vns SET c_private = p.private FROM p
     WHERE ulist_vns.uid = p.uid AND ulist_vns.vid = p.vid AND ulist_vns.c_private <> p.private;
END;
$$ LANGUAGE plpgsql;



-- Update tags_vn_direct & tags_vn_inherit.
-- When a vid is given, only the tags for that vid will be updated. These
-- incremental updates do not affect tags.c_items, so that may still get
-- out-of-sync.
CREATE OR REPLACE FUNCTION tag_vn_calc(uvid vndbid) RETURNS void AS $$
BEGIN
  -- tags_vn_direct
  WITH new (tag, vid, rating, count, spoiler, lie) AS (
    -- Rows that we want
    SELECT tv.tag, tv.vid
           -- https://vndb.org/t13470.28 -> (z || 3) * ((x-y) / (x+y))
           -- No exception is made for the x==y case, a score of 0 seems better to me.
         , (COALESCE(AVG(tv.vote) filter (where tv.vote > 0), 3) * SUM(sign(tv.vote)) / COUNT(tv.vote))::real
         , LEAST( COUNT(tv.vote) filter (where tv.vote > 0), 32000 )::smallint
         , CASE WHEN COUNT(spoiler) = 0 THEN MIN(t.defaultspoil) WHEN AVG(spoiler) > 1.3 THEN 2 WHEN AVG(spoiler) > 0.4 THEN 1 ELSE 0 END
         , count(lie) filter(where lie) > 0 AND count(lie) filter (where lie) >= count(lie) filter(where not lie)
      FROM tags_vn tv
	  JOIN tags t ON t.id = tv.tag
      LEFT JOIN users u ON u.id = tv.uid
     WHERE NOT t.hidden
       AND NOT tv.ignore AND (u.id IS NULL OR u.perm_tag)
       AND vid NOT IN(SELECT id FROM vn WHERE hidden)
       AND (uvid IS NULL OR vid = uvid)
     GROUP BY tv.tag, tv.vid
    HAVING SUM(sign(tv.vote)) > 0
  ), n AS (
    -- Add existing rows from tags_vn_direct as NULLs, so we can delete them during merge
    SELECT coalesce(a.tag, b.tag) AS tag, coalesce(a.vid, b.vid) AS vid, a.rating, a.count, a.spoiler, a.lie
      FROM new a
      FULL OUTER JOIN (SELECT tag, vid FROM tags_vn_direct WHERE uvid IS NULL OR vid = uvid) b on (a.tag, a.vid) = (b.tag, b.vid)
    -- Now merge
  ) MERGE INTO tags_vn_direct o USING n ON (n.tag, n.vid) = (o.tag, o.vid)
     WHEN NOT MATCHED THEN INSERT (tag, vid, rating, count, spoiler, lie) VALUES (n.tag, n.vid, n.rating, (n)."count", n.spoiler, n.lie)
     WHEN MATCHED AND n.rating IS NULL THEN DELETE
     WHEN MATCHED AND (o.rating, o.count, o.spoiler, o.lie) IS DISTINCT FROM (n.rating, n.count, n.spoiler, n.lie) THEN
       UPDATE SET rating = n.rating, count = n.count, spoiler = n.spoiler, lie = n.lie;

  -- tags_vn_inherit, based on the data from tags_vn_direct
  WITH new (tag, vid, rating, spoiler, lie) AS (
      -- Add parent tags to tags_vn_direct
     WITH RECURSIVE t_all(lvl, tag, vid, vote, spoiler, lie) AS (
            SELECT 15, tag, vid, rating, spoiler, lie
              FROM tags_vn_direct
             WHERE (uvid IS NULL OR vid = uvid)
            UNION ALL
            SELECT ta.lvl-1, tp.parent, ta.vid, ta.vote, ta.spoiler, ta.lie
              FROM t_all ta
              JOIN tags_parents tp ON tp.id = ta.tag
             WHERE ta.lvl > 0
      -- Merge duplicates
      ) SELECT tag, vid, AVG(vote)::real, MIN(spoiler), bool_and(lie)
          FROM t_all
         WHERE tag IN(SELECT id FROM tags WHERE searchable)
         GROUP BY tag, vid
  ), n AS (
    -- Add existing rows from tags_vn_inherit as NULLs, so we can delete them during merge
    SELECT coalesce(a.tag, b.tag) AS tag, coalesce(a.vid, b.vid) AS vid, a.rating, a.spoiler, a.lie
      FROM new a
      FULL OUTER JOIN (SELECT tag, vid FROM tags_vn_inherit WHERE uvid IS NULL OR vid = uvid) b on (a.tag, a.vid) = (b.tag, b.vid)
    -- Now merge
  ) MERGE INTO tags_vn_inherit o USING n ON (n.tag, n.vid) = (o.tag, o.vid)
     WHEN NOT MATCHED THEN INSERT (tag, vid, rating, spoiler, lie) VALUES (n.tag, n.vid, n.rating, n.spoiler, n.lie)
     WHEN MATCHED AND n.rating IS NULL THEN DELETE
     WHEN MATCHED AND (o.rating, o.spoiler, o.lie) IS DISTINCT FROM (n.rating, n.spoiler, n.lie) THEN
       UPDATE SET rating = n.rating, spoiler = n.spoiler, lie = n.lie;

  IF uvid IS NULL THEN
    UPDATE tags SET c_items = (SELECT COUNT(*) FROM tags_vn_inherit WHERE tag = id);
  END IF;
  RETURN;
END;
$$ LANGUAGE plpgsql;



-- Recalculate traits_chars. Pretty much same thing as tag_vn_calc().
CREATE OR REPLACE FUNCTION traits_chars_calc(ucid vndbid) RETURNS void AS $$
BEGIN
  WITH new (tid, cid, spoil, lie) AS (
    -- all char<->trait links of the latest revisions, including chars inherited from child traits.
    -- (also includes non-searchable traits, because they could have a searchable trait as parent)
    WITH RECURSIVE t_all(lvl, tid, cid, spoiler, lie) AS (
        SELECT 15, tid, ct.id, spoil, lie
          FROM chars_traits ct
         WHERE id NOT IN(SELECT id from chars WHERE hidden)
           AND (ucid IS NULL OR ct.id = ucid)
           AND NOT EXISTS (SELECT 1 FROM traits t WHERE t.id = ct.tid AND t.hidden)
      UNION ALL
        SELECT lvl-1, tp.parent, tc.cid, tc.spoiler, tc.lie
        FROM t_all tc
        JOIN traits_parents tp ON tp.id = tc.tid
        JOIN traits t ON t.id = tp.parent
        WHERE NOT t.hidden
          AND tc.lvl > 0
    )
    -- now grouped by (tid, cid), with non-searchable traits filtered out
    SELECT tid, cid
         , (CASE WHEN MIN(spoiler) > 1.3 THEN 2 WHEN MIN(spoiler) > 0.7 THEN 1 ELSE 0 END)::smallint
         , bool_and(lie)
      FROM t_all
     WHERE tid IN(SELECT id FROM traits WHERE searchable)
     GROUP BY tid, cid
  ), n AS (
    -- Add existing rows from traits_chars as NULLs, so we can delete them during merge
    SELECT coalesce(a.tid, b.tid) AS tid, coalesce(a.cid, b.cid) AS cid, a.spoil, a.lie
      FROM new a
      FULL OUTER JOIN (SELECT tid, cid FROM traits_chars WHERE ucid IS NULL OR cid = ucid) b on (a.tid, a.cid) = (b.tid, b.cid)
    -- Now merge
  ) MERGE INTO traits_chars o USING n ON (n.tid, n.cid) = (o.tid, o.cid)
     WHEN NOT MATCHED THEN INSERT (tid, cid, spoil, lie) VALUES (n.tid, n.cid, n.spoil, n.lie)
     WHEN MATCHED AND n.spoil IS NULL THEN DELETE
     WHEN MATCHED AND (o.spoil, o.lie) IS DISTINCT FROM (n.spoil, n.lie) THEN
       UPDATE SET spoil = n.spoil, lie = n.lie;

  IF ucid IS NULL THEN
    UPDATE traits SET c_items = (SELECT COUNT(*) FROM traits_chars WHERE tid = id);
  END IF;
  RETURN;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION quotes_rand_calc() RETURNS void AS $$
  WITH q(id, vid, score) AS (
    SELECT id, vid, score FROM quotes q WHERE score > 0 AND NOT hidden AND EXISTS(SELECT 1 FROM vn v WHERE v.id = q.vid AND NOT v.hidden)
  ), r(id,rand) AS (
    SELECT id, -- 'rand' is chosen such that each VN has an equal probability to be selected, regardless of how many quotes it has.
           ( ((dense_rank() OVER (ORDER BY vid)) - 1)::real -- [0..n-1] cumulative count of distinct VNs
             + ((sum(score) OVER (PARTITION BY vid ORDER BY id) - score)::float / (sum(score) OVER (PARTITION BY vid))) -- [0,1) cumulative normalized score of this quote
           ) / (SELECT count(DISTINCT vid) FROM q)
      FROM q
  ), u AS (
    UPDATE quotes SET rand = NULL WHERE rand IS NOT NULL AND NOT EXISTS(SELECT 1 FROM r WHERE quotes.id = r.id)
  ) UPDATE quotes SET rand = r.rand FROM r WHERE quotes.rand IS DISTINCT FROM r.rand AND r.id = quotes.id;
$$ LANGUAGE SQL;



-- Fully recalculate all rows in stats_cache
CREATE OR REPLACE FUNCTION update_stats_cache_full() RETURNS void AS $$
BEGIN
  UPDATE stats_cache SET count = (SELECT COUNT(*) FROM vn        WHERE hidden = FALSE) WHERE section = 'vn';
  UPDATE stats_cache SET count = (SELECT COUNT(*) FROM releases  WHERE hidden = FALSE) WHERE section = 'releases';
  UPDATE stats_cache SET count = (SELECT COUNT(*) FROM producers WHERE hidden = FALSE) WHERE section = 'producers';
  UPDATE stats_cache SET count = (SELECT COUNT(*) FROM chars     WHERE hidden = FALSE) WHERE section = 'chars';
  UPDATE stats_cache SET count = (SELECT COUNT(*) FROM staff     WHERE hidden = FALSE) WHERE section = 'staff';
  UPDATE stats_cache SET count = (SELECT COUNT(*) FROM tags      WHERE hidden = FALSE) WHERE section = 'tags';
  UPDATE stats_cache SET count = (SELECT COUNT(*) FROM traits    WHERE hidden = FALSE) WHERE section = 'traits';
END;
$$ LANGUAGE plpgsql;


-- Create ulist labels for new users.
CREATE OR REPLACE FUNCTION ulist_labels_create(vndbid) RETURNS void AS $$
  INSERT INTO ulist_labels (uid, id, label, private)
       VALUES ($1, 1, 'Playing',   false),
              ($1, 2, 'Finished',  false),
              ($1, 3, 'Stalled',   false),
              ($1, 4, 'Dropped',   false),
              ($1, 5, 'Wishlist',  false),
              ($1, 6, 'Blacklist', false),
              ($1, 7, 'Voted',     false)
  ON CONFLICT (uid, id) DO NOTHING;
$$ LANGUAGE SQL;


-- Returns generic information for almost every supported vndbid + num.
-- Not currently supported: ch#, cv#, sf#
-- Some oddities:
-- * The given user title preferences are not used for explicit revisions.
-- * Trait names are prefixed with their group name ("Group > Trait"), but only for non-revisions.
--
-- Returned fields:
--   * title    - Titles array, same format as returned by vnt().
--                For users this is their username, not displayname.
--   * uid      - User who created/initiated this entry. Used in notification listings and reports
--   * hidden   - Whether this entry is 'hidden' or private. Used for the reporting function & framework_ object.
--                For edits this info comes from the revision itself, not the final entry.
--                Interpretation of this field is dependent on the entry type, For most database entries,
--                'hidden' means "partially visible if you know the ID, but not shown in regular listings".
--                For threads it means "totally invisible, does not exist".
--   * locked   - Whether this entry is 'locked'. Used for the framework_ object.
CREATE OR REPLACE FUNCTION item_info(titleprefs, vndbid, int, out ret item_info_type) AS $$
BEGIN
  -- x#
  IF $3 IS NULL THEN CASE vndbid_type($2)
    WHEN 'v' THEN SELECT v.title, NULL::vndbid, v.hidden, v.locked INTO ret FROM vnt($1) v        WHERE v.id = $2;
    WHEN 'r' THEN SELECT r.title, NULL::vndbid, r.hidden, r.locked INTO ret FROM releasest($1) r  WHERE r.id = $2;
    WHEN 'p' THEN SELECT p.title, NULL::vndbid, p.hidden, p.locked INTO ret FROM producerst($1) p WHERE p.id = $2;
    WHEN 'c' THEN SELECT c.title, NULL::vndbid, c.hidden, c.locked INTO ret FROM charst($1) c     WHERE c.id = $2;
    WHEN 'd' THEN SELECT ARRAY[NULL, d.title, NULL, d.title], NULL::vndbid, d.hidden, d.locked INTO ret FROM docs d WHERE d.id = $2;
    WHEN 'g' THEN SELECT ARRAY[NULL, g.name,  NULL, g.name],  NULL::vndbid, g.hidden, g.locked INTO ret FROM tags g WHERE g.id = $2;
    WHEN 'i' THEN SELECT ARRAY[NULL, COALESCE(g.name||' > ', '')||i.name, NULL, COALESCE(g.name||' > ', '')||i.name], NULL::vndbid, i.hidden, i.locked INTO ret FROM traits i LEFT JOIN traits g ON g.id = i.gid WHERE i.id = $2;
    WHEN 's' THEN SELECT s.title, NULL::vndbid, s.hidden, s.locked INTO ret FROM staff_aliast($1) s WHERE s.id = $2 AND s.aid = s.main;
    WHEN 't' THEN SELECT ARRAY[NULL, t.title, NULL, t.title], NULL::vndbid, t.hidden OR t.private, t.locked INTO ret FROM threads t WHERE t.id = $2;
    WHEN 'w' THEN SELECT v.title, w.uid, w.c_flagged, w.locked INTO ret FROM reviews w JOIN vnt v ON v.id = w.vid WHERE w.id = $2;
    WHEN 'u' THEN SELECT ARRAY[NULL, COALESCE(u.username, u.id::text), NULL, COALESCE(u.username, u.id::text)], NULL::vndbid, u.username IS NULL, FALSE INTO ret FROM users u WHERE u.id = $2;
    ELSE NULL;
  END CASE;
  -- x#.#
  ELSE CASE vndbid_type($2)
    WHEN 'v' THEN SELECT ARRAY[v.olang::text, COALESCE(vo.latin, vo.title), v.olang::text, CASE WHEN vo.latin IS NULL THEN '' ELSE vo.title END], h.requester, h.ihid, h.ilock INTO ret
                    FROM changes h JOIN vn_hist v ON h.id = v.chid JOIN vn_titles_hist vo ON h.id = vo.chid AND vo.lang = v.olang WHERE h.itemid = $2 AND h.rev = $3;
    WHEN 'r' THEN SELECT ARRAY[r.olang::text, COALESCE(ro.latin, ro.title), r.olang::text, CASE WHEN ro.latin IS NULL THEN '' ELSE ro.title END], h.requester, h.ihid, h.ilock INTO ret
                    FROM changes h JOIN releases_hist r ON h.id = r.chid JOIN releases_titles_hist ro ON h.id = ro.chid AND ro.lang = r.olang WHERE h.itemid = $2 AND h.rev = $3;
    WHEN 'p' THEN SELECT ARRAY[p.lang::text, COALESCE(p.latin, p.name), p.lang::text, p.name], h.requester, h.ihid, h.ilock INTO ret FROM changes h JOIN producers_hist p ON h.id = p.chid WHERE h.itemid = $2 AND h.rev = $3;
    WHEN 'c' THEN SELECT ARRAY[cm.c_lang::text, COALESCE(c.latin, c.name), cm.c_lang::text, c.name], h.requester, h.ihid, h.ilock INTO ret FROM changes h JOIN chars cm ON cm.id = h.itemid JOIN chars_hist c ON h.id = c.chid WHERE h.itemid = $2 AND h.rev = $3;
    WHEN 'd' THEN SELECT ARRAY[NULL, d.title, NULL, d.title   ],  h.requester, h.ihid, h.ilock INTO ret FROM changes h JOIN docs_hist d   ON h.id = d.chid WHERE h.itemid = $2 AND h.rev = $3;
    WHEN 'g' THEN SELECT ARRAY[NULL, g.name,  NULL, g.name    ],  h.requester, h.ihid, h.ilock INTO ret FROM changes h JOIN tags_hist g   ON h.id = g.chid WHERE h.itemid = $2 AND h.rev = $3;
    WHEN 'i' THEN SELECT ARRAY[NULL, i.name,  NULL, i.name    ],  h.requester, h.ihid, h.ilock INTO ret FROM changes h JOIN traits_hist i ON h.id = i.chid WHERE h.itemid = $2 AND h.rev = $3;
    WHEN 's' THEN SELECT ARRAY[s.lang::text, COALESCE(sa.latin, sa.name), s.lang::text, sa.name], h.requester, h.ihid, h.ilock INTO ret FROM changes h JOIN staff_hist s     ON h.id = s.chid JOIN staff_alias_hist sa ON sa.chid = s.chid AND sa.aid = s.main WHERE h.itemid = $2 AND h.rev = $3;
    WHEN 't' THEN SELECT ARRAY[NULL, t.title, NULL, t.title], tp.uid, t.hidden OR t.private OR tp.hidden IS NOT NULL, t.locked INTO ret FROM threads t JOIN threads_posts tp ON tp.tid = t.id WHERE t.id = $2 AND tp.num = $3;
    WHEN 'w' THEN SELECT v.title, wp.uid, w.c_flagged OR wp.hidden IS NOT NULL, w.locked INTO ret FROM reviews w JOIN vnt($1) v ON v.id = w.vid JOIN reviews_posts wp ON wp.id = w.id WHERE w.id = $2 AND wp.num = $3;
    ELSE NULL;
  END CASE;
  END IF;
END;
$$ LANGUAGE plpgsql STABLE;



----------------------------------------------------------
--           revision insertion abstraction             --
----------------------------------------------------------

-- The two functions below are utility functions used by the item-specific functions in editfunc.sql

-- create temporary table for generic revision info, and returns the chid of the revision being edited (or NULL).
CREATE OR REPLACE FUNCTION edit_revtable(xitemid vndbid, xrev integer) RETURNS integer AS $$
DECLARE
  x record;
BEGIN
  BEGIN
    CREATE TEMPORARY TABLE edit_revision (
      itemid vndbid,
      requester vndbid,
      comments text,
      ihid boolean,
      ilock boolean
    );
  EXCEPTION WHEN duplicate_table THEN
    TRUNCATE edit_revision;
  END;
  SELECT INTO x id, ihid, ilock FROM changes c WHERE itemid = xitemid AND rev = xrev;
  INSERT INTO edit_revision (itemid, ihid, ilock) VALUES (xitemid, COALESCE(x.ihid, FALSE), COALESCE(x.ilock, FALSE));
  RETURN x.id;
END;
$$ LANGUAGE plpgsql;


-- Check for stuff to be done when an item has been changed
CREATE OR REPLACE FUNCTION edit_committed(nchid integer, nitemid vndbid, nrev integer) RETURNS void AS $$
DECLARE
  xoldchid integer;
BEGIN
  SELECT id INTO xoldchid FROM changes WHERE itemid = nitemid AND rev = nrev-1;

  -- Update search_cache
  IF vndbid_type(nitemid) IN('v','r','c','p','s','g','i') THEN
    PERFORM update_search(nitemid);
  END IF;

  -- Update search_cache for related VNs when
  -- 1. A new release is created
  -- 2. A release has been hidden or unhidden
  -- 3. The releases_titles have changed
  -- 4. The releases_vn table differs from a previous revision
  IF vndbid_type(nitemid) = 'r' THEN
    IF -- 1.
       xoldchid IS NULL OR
       -- 2.
       EXISTS(SELECT 1 FROM changes c1, changes c2 WHERE c1.ihid IS DISTINCT FROM c2.ihid AND c1.id = nchid AND c2.id = xoldchid) OR
       -- 3.
       EXISTS(SELECT title, latin FROM releases_titles_hist WHERE chid = xoldchid EXCEPT SELECT title, latin FROM releases_titles_hist WHERE chid = nchid) OR
       EXISTS(SELECT title, latin FROM releases_titles_hist WHERE chid = nchid    EXCEPT SELECT title, latin FROM releases_titles_hist WHERE chid = xoldchid) OR
       -- 4.
       EXISTS(SELECT vid FROM releases_vn_hist WHERE chid = xoldchid EXCEPT SELECT vid FROM releases_vn_hist WHERE chid = nchid) OR
       EXISTS(SELECT vid FROM releases_vn_hist WHERE chid = nchid    EXCEPT SELECT vid FROM releases_vn_hist WHERE chid = xoldchid)
    THEN
      PERFORM update_search(vid) FROM releases_vn_hist WHERE chid IN(nchid, xoldchid);
    END IF;
  END IF;

  -- Update drm.c_ref
  IF vndbid_type(nitemid) = 'r' THEN
    WITH
      old (id) AS (SELECT r.drm FROM releases_drm_hist r, changes c WHERE r.chid = xoldchid AND c.id = xoldchid AND NOT c.ihid),
      new (id) AS (SELECT r.drm FROM releases_drm_hist r, changes c WHERE r.chid = nchid    AND c.id = nchid    AND NOT c.ihid),
      ins      AS (UPDATE drm SET c_ref = c_ref + 1 WHERE id IN(SELECT id FROM new EXCEPT SELECT id FROM old))
                   UPDATE drm SET c_ref = c_ref - 1 WHERE id IN(SELECT id FROM old EXCEPT SELECT id FROM new);
  END IF;

  -- Update tags_vn_* when the VN's hidden flag is changed
  IF vndbid_type(nitemid) = 'v' AND EXISTS(SELECT 1 FROM changes c1, changes c2 WHERE c1.ihid IS DISTINCT FROM c2.ihid AND c1.id = nchid AND c2.id = xoldchid) THEN
    PERFORM tag_vn_calc(nitemid);
  END IF;

  -- Ensure chars.c_lang is updated when the related VN or char has been edited
  -- (the cache also depends on vn.c_released but isn't run when that is updated;
  -- not an issue, the c_released is only there as rare fallback)
  IF vndbid_type(nitemid) IN('c','v') THEN
    WITH x(id,lang) AS (
      SELECT DISTINCT ON (cv.id) cv.id, v.olang
        FROM chars_vns cv
        JOIN vn v ON v.id = cv.vid
       WHERE cv.vid = nitemid OR cv.id = nitemid
       ORDER BY cv.id, v.hidden, v.c_released
    ) UPDATE chars c SET c_lang = x.lang FROM x WHERE c.id = x.id AND c.c_lang <> x.lang;
  END IF;

  -- Call update_vncache() for related VNs when a release has been created or edited
  -- (This could be made more specific, but update_vncache() is fast enough that it's not worth the complexity)
  IF vndbid_type(nitemid) = 'r' THEN
    PERFORM update_vncache(vid) FROM (
      SELECT DISTINCT vid FROM releases_vn_hist WHERE chid IN(nchid, xoldchid)
    ) AS v(vid);
  END IF;

  -- Call traits_chars_calc() for characters to update the traits cache
  IF vndbid_type(nitemid) = 'c' THEN
    PERFORM traits_chars_calc(nitemid);
  END IF;

  -- Create edit notifications
  INSERT INTO notifications (uid, ntype, iid, num)
       SELECT n.uid, n.ntype, n.iid, n.num FROM changes c, notify(nitemid, c.rev, c.requester) n WHERE c.id = nchid;

  -- Make sure all visual novels linked to a release have a corresponding entry
  -- in ulist_vns for users who have the release in rlists. This is action (3) in
  -- update_vnlist_rlist().
  IF vndbid_type(nitemid) = 'r' AND xoldchid IS NOT NULL
  THEN
    INSERT INTO ulist_vns (uid, vid)
      SELECT rl.uid, rv.vid FROM rlists rl JOIN releases_vn rv ON rv.id = rl.rid WHERE rl.rid = nitemid
    ON CONFLICT (uid, vid) DO NOTHING;
  END IF;

  -- Call update_images_cache() where appropriate
  IF vndbid_type(nitemid) = 'c'
  THEN
    PERFORM update_images_cache(image) FROM chars_hist WHERE chid IN(xoldchid,nchid) AND image IS NOT NULL;
  END IF;
  IF vndbid_type(nitemid) = 'v'
  THEN
    PERFORM update_images_cache(image) FROM vn_hist WHERE chid IN(xoldchid,nchid) AND image IS NOT NULL;
    PERFORM update_images_cache(scr) FROM vn_screenshots_hist WHERE chid IN(xoldchid,nchid);
  END IF;
END;
$$ LANGUAGE plpgsql;




----------------------------------------------------------
--                notification functions                --
----------------------------------------------------------


-- Called after a certain event has occurred (new edit, post, etc).
--  'iid' and 'num' identify the item that has been created.
--  'uid' indicates who created the item, providing an easy method of not creating a notification for that user.
--     (can technically be fetched with a DB lookup, too)
CREATE OR REPLACE FUNCTION notify(iid vndbid, num integer, uid vndbid) RETURNS TABLE (uid vndbid, ntype notification_ntype[], iid vndbid, num int) AS $$
  SELECT uid, array_agg(ntype), $1, $2
    FROM (

      -- pm
      SELECT 'pm'::notification_ntype, u.id
        FROM threads_boards tb
        JOIN users u ON u.id = tb.iid
       WHERE vndbid_type($1) = 't' AND tb.tid = $1 AND tb.type = 'u'
         AND NOT EXISTS(SELECT 1 FROM notification_subs ns WHERE ns.iid = $1 AND ns.uid = tb.iid AND ns.subnum = false)

      -- dbdel
      UNION
      SELECT 'dbdel', c_all.requester
        FROM changes c_cur, changes c_all, changes c_pre
       WHERE c_cur.itemid = $1 AND c_cur.rev = $2   -- Current edit
         AND c_pre.itemid = $1 AND c_pre.rev = $2-1 -- Previous edit, to check if .ihid changed
         AND c_all.itemid = $1 -- All edits on this entry, to see whom to notify
         AND c_cur.ihid AND NOT c_pre.ihid
         AND $2 > 1 AND vndbid_type($1) IN('v', 'r', 'p', 'c', 's', 'd', 'g', 'i')

      -- listdel
      UNION
      SELECT 'listdel', u.uid
        FROM changes c_cur, changes c_pre,
             ( SELECT uid FROM ulist_vns WHERE vndbid_type($1) = 'v' AND vid = $1 -- TODO: Could use an index on ulist_vns.vid
               UNION ALL
               SELECT uid FROM rlists    WHERE vndbid_type($1) = 'r' AND rid = $1 -- TODO: Could also use an index, but the rlists table isn't that large so it's still okay
             ) u(uid)
       WHERE c_cur.itemid = $1 AND c_cur.rev = $2   -- Current edit
         AND c_pre.itemid = $1 AND c_pre.rev = $2-1 -- Previous edit, to check if .ihid changed
         AND c_cur.ihid AND NOT c_pre.ihid
         AND $2 > 1 AND vndbid_type($1) IN('v','r')

      -- dbedit
      UNION
      SELECT 'dbedit', c.requester
        FROM changes c
        JOIN users u ON u.id = c.requester
       WHERE c.itemid = $1
         AND $2 > 1 AND vndbid_type($1) IN('v', 'r', 'p', 'c', 's', 'd', 'g', 'i')
         AND $3 <> 'u1' -- Exclude edits by Multi
         AND u.notify_dbedit
         AND NOT EXISTS(SELECT 1 FROM notification_subs ns WHERE ns.iid = $1 AND ns.uid = c.requester AND ns.subnum = false)

      -- subedit
      UNION
      SELECT 'subedit', ns.uid
        FROM notification_subs ns
       WHERE $2 > 1 AND vndbid_type($1) IN('v', 'r', 'p', 'c', 's', 'd', 'g', 'i')
         AND $3 <> 'u1' -- Exclude edits by Multi
         AND ns.iid = $1 AND ns.subnum

      -- announce
      UNION
      SELECT 'announce', u.id
        FROM threads t
        JOIN threads_boards tb ON tb.tid = t.id
        JOIN users u ON u.notify_announce
       WHERE vndbid_type($1) = 't' AND $2 = 1 AND t.id = $1 AND tb.type = 'an'

      -- post (threads_posts)
      UNION
      SELECT 'post', u.id
        FROM threads t, threads_posts tp
        JOIN users u ON tp.uid = u.id
       WHERE t.id = $1 AND tp.tid = $1 AND vndbid_type($1) = 't' AND $2 > 1 AND NOT t.private AND NOT t.hidden AND u.notify_post
         AND NOT EXISTS(SELECT 1 FROM notification_subs ns WHERE ns.iid = $1 AND ns.uid = tp.uid AND ns.subnum = false)

      -- post (reviews_posts)
      UNION
      SELECT 'post', u.id
        FROM reviews_posts wp
        JOIN users u ON wp.uid = u.id
       WHERE wp.id = $1 AND vndbid_type($1) = 'w' AND $2 IS NOT NULL AND u.notify_post
         AND NOT EXISTS(SELECT 1 FROM notification_subs ns WHERE ns.iid = $1 AND ns.uid = wp.uid AND ns.subnum = false)

      -- subpost (threads_posts)
      UNION
      SELECT 'subpost', ns.uid
        FROM threads t, notification_subs ns
       WHERE t.id = $1 AND ns.iid = $1 AND vndbid_type($1) = 't' AND $2 > 1 AND NOT t.private AND NOT t.hidden AND ns.subnum

      -- subpost (reviews_posts)
      UNION
      SELECT 'subpost', ns.uid
        FROM notification_subs ns
       WHERE ns.iid = $1 AND vndbid_type($1) = 'w' AND $2 IS NOT NULL AND ns.subnum

      -- comment
      UNION
      SELECT 'comment', u.id
        FROM reviews w
        JOIN users u ON w.uid = u.id
       WHERE w.id = $1 AND vndbid_type($1) = 'w' AND $2 IS NOT NULL AND u.notify_comment
         AND NOT EXISTS(SELECT 1 FROM notification_subs ns WHERE ns.iid = $1 AND ns.uid = w.uid AND NOT ns.subnum)

      -- subreview
      UNION
      SELECT 'subreview', ns.uid
        FROM reviews w, notification_subs ns
       WHERE w.id = $1 AND vndbid_type($1) = 'w' AND $2 IS NULL AND ns.iid = w.vid AND ns.subreview

      -- subapply
      UNION
      SELECT 'subapply', uid
        FROM notification_subs
       WHERE subapply AND vndbid_type($1) = 'c' AND $2 IS NOT NULL
         AND iid IN(
              WITH new(tid) AS (SELECT tid FROM chars_traits_hist WHERE chid = (SELECT id FROM changes WHERE itemid = $1 AND rev = $2)),
                   old(tid) AS (SELECT tid FROM chars_traits_hist WHERE chid = (SELECT id FROM changes WHERE itemid = $1 AND $2 > 1 AND rev = $2-1))
              (SELECT tid FROM old EXCEPT SELECT tid FROM new) UNION (SELECT tid FROM new EXCEPT SELECT tid FROM old)
            )

    ) AS noti(ntype, uid)
   WHERE uid <> $3
     AND uid <> 'u1' -- No announcements for Multi
   GROUP BY uid;
$$ LANGUAGE SQL;




----------------------------------------------------------
--                    user management                   --
----------------------------------------------------------
-- XXX: These functions run with the permissions of the 'vndb' user.


-- Returns the raw scrypt parameters (N, r, p and salt) for this user, in order
-- to create an encrypted pass. Returns NULL if this user does not have a valid
-- password.
CREATE OR REPLACE FUNCTION user_getscryptargs(vndbid) RETURNS bytea AS $$
  SELECT
    CASE WHEN length(passwd) = 46 THEN substring(passwd from 1 for 14) ELSE NULL END
  FROM users_shadow WHERE id = $1
$$ LANGUAGE SQL SECURITY DEFINER;


-- Create a new session for this user (uid, type, scryptpass, token)
CREATE OR REPLACE FUNCTION user_login(vndbid, session_type, bytea, bytea) RETURNS boolean AS $$
  INSERT INTO sessions (uid, token, expires, type) SELECT $1, $4, NOW() + '1 month', $2 FROM users_shadow
   WHERE length($3) = 46 AND length($4) = 20
     AND id = $1 AND passwd = $3 AND $2 IN('web', 'api')
  RETURNING true
$$ LANGUAGE SQL SECURITY DEFINER;


CREATE OR REPLACE FUNCTION user_logout(vndbid, bytea) RETURNS void AS $$
  DELETE FROM sessions WHERE uid = $1 AND token = $2 AND type IN('web','api')
$$ LANGUAGE SQL SECURITY DEFINER;


-- BIG WARNING: Do not use "IS NOT NULL" on the return value, it'll always
-- evaluate to false. Use 'IS DISTINCT FROM NULL' instead.
CREATE OR REPLACE FUNCTION user_validate_session(vndbid, bytea, session_type) RETURNS sessions AS $$
  -- Extends the expiration time of web and api sessions.
  UPDATE sessions SET expires = NOW() + '1 month'
   WHERE uid = $1 AND token = $2 AND type = $3 AND $3 IN('web', 'api')
     AND expires < NOW() + '1 month'::interval - '6 hours'::interval;
  -- Update last use date for api2 sessions
  UPDATE sessions SET expires = NOW()
   WHERE uid = $1 AND token = $2 AND type = $3 AND $3 = 'api2'
     AND (expires = added OR expires::date < 'today'::date);
  SELECT * FROM sessions WHERE uid = $1 AND token = $2 AND type = $3
$$ LANGUAGE SQL SECURITY DEFINER;


-- Used for duplicate email checks and user-by-email lookup for usermods.
CREATE OR REPLACE FUNCTION user_emailtoid(text) RETURNS TABLE (uid vndbid, mail text) AS $$
  SELECT id, mail FROM users_shadow WHERE hash_email(mail) = hash_email($1)
$$ LANGUAGE SQL SECURITY DEFINER ROWS 1;


-- Store a password reset token. args: email, token. Returns: user id, actual email.
-- Doesn't work for usermods, otherwise an attacker could use this function to
-- gain access to all user's emails by obtaining a reset token of a usermod.
-- Ideally Postgres itself would send the user an email so that the application
-- calling this function doesn't even get the token, and thus can't get access
-- to someone's account. But alas, that'd require a separate process.
CREATE OR REPLACE FUNCTION user_resetpass(text, bytea, OUT vndbid, OUT text) AS $$
  INSERT INTO sessions (uid, token, expires, type)
    SELECT id, $2, NOW()+'1 week', 'pass' FROM users_shadow
     WHERE hash_email(mail) = hash_email($1) AND length($2) = 20 AND NOT perm_usermod
    RETURNING uid, mail
$$ LANGUAGE SQL SECURITY DEFINER;


-- Changes the user's password and invalidates all existing sessions. args: uid, old_pass_or_reset_token, new_pass
CREATE OR REPLACE FUNCTION user_setpass(vndbid, bytea, bytea) RETURNS boolean AS $$
  WITH upd(id) AS (
    UPDATE users_shadow SET passwd = $3
     WHERE id = $1
       AND length($3) = 46
       AND (    (passwd = $2 AND length($2) = 46)
             OR EXISTS(SELECT 1 FROM sessions WHERE uid = $1 AND token = $2 AND type = 'pass' AND expires > NOW())
           )
    RETURNING id
  ), del AS( -- Not referenced, but still guaranteed to run
    DELETE FROM sessions WHERE uid IN(SELECT id FROM upd) AND type <> 'api2'
  )
  SELECT true FROM upd
$$ LANGUAGE SQL SECURITY DEFINER;


-- Internal function, used to verify whether user ($2 with session $3) is
-- allowed to access sensitive data from user $1.
CREATE OR REPLACE FUNCTION user_isauth(vndbid, vndbid, bytea) RETURNS boolean AS $$
  SELECT true FROM users_shadow
   WHERE id = $2
     AND EXISTS(SELECT 1 FROM sessions WHERE uid = $2 AND token = $3 AND type = 'web')
     AND ($2 IS NOT DISTINCT FROM $1 OR perm_usermod)
$$ LANGUAGE SQL;


-- uid of user email to get, uid currently logged in, session token of currently logged in.
-- Ensures that only the user itself or a useradmin can get someone's email address.
CREATE OR REPLACE FUNCTION user_getmail(vndbid, vndbid, bytea) RETURNS text AS $$
  SELECT mail FROM users_shadow WHERE id = $1 AND user_isauth($1, $2, $3)
$$ LANGUAGE SQL SECURITY DEFINER;


-- Set a token to change a user's email address.
-- Args: uid, web-token, new-email-token, email
CREATE OR REPLACE FUNCTION user_setmail_token(vndbid, bytea, bytea, text) RETURNS void AS $$
  INSERT INTO sessions (uid, token, expires, type, mail)
    SELECT id, $3, NOW()+'1 week', 'mail', $4 FROM users
     WHERE id = $1 AND user_isauth($1, $1, $2) AND length($3) = 20
$$ LANGUAGE SQL SECURITY DEFINER;


-- Actually change a user's email address, given a valid token.
CREATE OR REPLACE FUNCTION user_setmail_confirm(vndbid, bytea) RETURNS boolean AS $$
  WITH u(mail) AS (
    DELETE FROM sessions WHERE uid = $1 AND token = $2 AND type = 'mail' AND expires > NOW() RETURNING mail
  )
  UPDATE users_shadow SET mail = (SELECT mail FROM u) WHERE id = $1 AND EXISTS(SELECT 1 FROM u) RETURNING true;
$$ LANGUAGE SQL SECURITY DEFINER;


CREATE OR REPLACE FUNCTION user_setperm_usermod(vndbid, vndbid, bytea, boolean) RETURNS void AS $$
  UPDATE users_shadow SET perm_usermod = $4 WHERE id = $1 AND user_isauth(NULL, $2, $3)
$$ LANGUAGE SQL SECURITY DEFINER;


CREATE OR REPLACE FUNCTION user_admin_setpass(vndbid, vndbid, bytea, bytea) RETURNS void AS $$
  WITH upd(id) AS (
    UPDATE users_shadow SET passwd = $4 WHERE id = $1 AND user_isauth(NULL, $2, $3) AND length($4) = 46 RETURNING id
  )
  DELETE FROM sessions WHERE uid IN(SELECT id FROM upd)
$$ LANGUAGE SQL SECURITY DEFINER;


CREATE OR REPLACE FUNCTION user_admin_setmail(vndbid, vndbid, bytea, text) RETURNS void AS $$
  UPDATE users_shadow SET mail = $4 WHERE id = $1 AND user_isauth(NULL, $2, $3)
$$ LANGUAGE SQL SECURITY DEFINER;


CREATE OR REPLACE FUNCTION user_api2_tokens(vndbid, vndbid, bytea) RETURNS SETOF sessions AS $$
  SELECT * FROM sessions WHERE uid = $1 AND type = 'api2' AND user_isauth($1, $2, $3)
$$ LANGUAGE SQL SECURITY DEFINER;


CREATE OR REPLACE FUNCTION user_api2_set_token(vndbid, vndbid, bytea, bytea, text, boolean, boolean) RETURNS void AS $$
  INSERT INTO sessions (uid, type, expires, token, notes, listread, listwrite)
                SELECT  $1,  'api2', NOW(), $4,    $5,    $6,       $7
                 WHERE user_isauth($1, $2, $3) AND length($4) = 20
  ON CONFLICT (uid, token) DO UPDATE SET notes = $5, listread = $6, listwrite = $7
$$ LANGUAGE SQL SECURITY DEFINER;


CREATE OR REPLACE FUNCTION user_api2_del_token(vndbid, vndbid, bytea, bytea) RETURNS void AS $$
  DELETE FROM sessions WHERE uid = $1 AND token = $4 AND user_isauth($1, $2, $3)
$$ LANGUAGE SQL SECURITY DEFINER;


CREATE OR REPLACE FUNCTION email_optout_check(text) RETURNS boolean AS $$
  SELECT EXISTS(SELECT 1 FROM email_optout WHERE mail = hash_email($1))
$$ LANGUAGE SQL SECURITY DEFINER;


-- Delete a user account.
-- A 'hard' delete means that the row in the 'users' table is also deleted and
-- any database contributions referring to this user will refer to NULL
-- instead.
-- A non-'hard' delete still deletes all account information but keeps the row
-- in the users table, so that we are still able to audit their database
-- contributions.
-- 'hard' can be set to NULL to do a hard delete when the user has not made any
-- relevant contributions and a soft delete otherwise.
CREATE OR REPLACE FUNCTION user_delete(userid vndbid, hard boolean) RETURNS void AS $$
BEGIN
  -- References can be audited with: grep 'REFERENCES users' sql/tableattrs.sql
  IF hard IS NULL THEN
    SELECT INTO hard NOT (
         EXISTS(SELECT 1 FROM changes           WHERE userid = requester)
      OR EXISTS(SELECT 1 FROM changes_patrolled WHERE userid = uid)
      OR EXISTS(SELECT 1 FROM images            WHERE userid = uploader)
      OR EXISTS(SELECT 1 FROM image_votes       WHERE userid = uid)
      OR EXISTS(SELECT 1 FROM quotes            WHERE userid = addedby)
      OR EXISTS(SELECT 1 FROM reports_log       WHERE userid = uid)
      OR EXISTS(SELECT 1 FROM reviews           WHERE userid = uid)
      OR EXISTS(SELECT 1 FROM reviews_posts     WHERE userid = uid)
      OR EXISTS(SELECT 1 FROM tags_vn           WHERE userid = uid)
      OR EXISTS(SELECT 1 FROM threads_posts     WHERE userid = uid)
      OR EXISTS(SELECT 1 FROM vn_length_votes   WHERE userid = uid));
  END IF;
  INSERT INTO email_optout (mail)
    SELECT hash_email(mail) FROM users_shadow WHERE id = userid
    ON CONFLICT (mail) DO NOTHING;
  -- Account-related data.
  -- (This is unnecessary for a hard delete due to the ON DELETE CASCADE
  -- constraint actions, but we need this code anyway for the soft deletes)
  DELETE FROM notification_subs WHERE uid = userid;
  DELETE FROM notifications WHERE uid = userid;
  DELETE FROM rlists WHERE uid = userid;
  DELETE FROM saved_queries WHERE uid = userid;
  DELETE FROM sessions WHERE uid = userid;
  DELETE FROM ulist_labels WHERE uid = userid;
  DELETE FROM ulist_vns WHERE uid = userid;
  DELETE FROM users_prefs WHERE id = userid;
  DELETE FROM users_prefs_tags WHERE id = userid;
  DELETE FROM users_prefs_traits WHERE id = userid;
  DELETE FROM users_shadow WHERE id = userid;
  DELETE FROM users_traits WHERE id = userid;
  DELETE FROM users_username_hist WHERE id = userid;
  IF hard THEN
    -- Delete votes that have been invalidated by a moderator, otherwise they will suddenly start counting again
    DELETE FROM reviews_votes      WHERE uid = userid AND NOT EXISTS(SELECT 1 FROM users WHERE id = userid AND ign_votes);
    DELETE FROM threads_poll_votes WHERE uid = userid AND NOT EXISTS(SELECT 1 FROM users WHERE id = userid AND ign_votes);
    DELETE FROM quotes_votes       WHERE uid = userid AND NOT EXISTS(SELECT 1 FROM users WHERE id = userid AND ign_votes);
    DELETE FROM tags_vn            WHERE uid = userid AND NOT EXISTS(SELECT 1 FROM users WHERE id = userid AND perm_tag);
    DELETE FROM vn_length_votes    WHERE uid = userid AND NOT EXISTS(SELECT 1 FROM users WHERE id = userid AND perm_lengthvote);
    DELETE FROM image_votes        WHERE uid = userid AND NOT EXISTS(SELECT 1 FROM users WHERE id = userid AND perm_imgvote);
    DELETE FROM users WHERE id = userid;
    INSERT INTO audit_log (affected_uid, action) VALUES (userid, 'hard delete');
  ELSE
    UPDATE users SET
        notify_dbedit = DEFAULT,
        notify_announce = DEFAULT,
        notify_post = DEFAULT,
        notify_comment = DEFAULT,
        nodistract_noads = DEFAULT,
        nodistract_nofancy = DEFAULT,
        support_enabled = DEFAULT,
        pubskin_enabled = DEFAULT,
        username = DEFAULT,
        uniname = DEFAULT
      WHERE id = userid;
    INSERT INTO audit_log (affected_uid, action) VALUES (userid, 'soft delete');
  END IF;
END
$$ LANGUAGE plpgsql;
