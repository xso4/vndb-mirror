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


CREATE OR REPLACE FUNCTION search_gen_vn(vnid vndbid) RETURNS text AS $$
  SELECT coalesce(string_agg(t, ' '), '') FROM (
    SELECT t FROM (
                SELECT search_norm_term(title) FROM vn_titles WHERE id = vnid
      UNION ALL SELECT search_norm_term(latin) FROM vn_titles WHERE id = vnid
      UNION ALL SELECT search_norm_term(a) FROM vn, regexp_split_to_table(alias, E'\n') a(a) WHERE vnid = id
      -- Remove the various editions/version strings from release titles,
      -- this reduces the index size and makes VN search more relevant.
      -- People looking for editions should be using the release search.
      UNION ALL SELECT regexp_replace(search_norm_term(t), '(?:
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
          SELECT title FROM releases r JOIN releases_vn rv ON rv.id = r.id JOIN releases_titles rt ON rt.id = r.id WHERE NOT r.hidden AND rv.vid = vnid
          UNION ALL
          SELECT latin FROM releases r JOIN releases_vn rv ON rv.id = r.id JOIN releases_titles rt ON rt.id = r.id WHERE NOT r.hidden AND rv.vid = vnid
        ) r(t)
    ) x(t) WHERE t IS NOT NULL AND t <> '' GROUP BY t ORDER BY t
  ) x(t);
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION search_gen_release(relid vndbid) RETURNS text AS $$
  SELECT coalesce(string_agg(t, ' '), '') FROM (
    SELECT t FROM (
                SELECT search_norm_term(title) FROM releases_titles WHERE id = relid
      UNION ALL SELECT search_norm_term(latin) FROM releases_titles WHERE id = relid
    ) x(t) WHERE t IS NOT NULL AND t <> '' GROUP BY t ORDER BY t
  ) x(t);
$$ LANGUAGE SQL;


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


-- Update vn.c_popularity, c_rating, c_votecount, c_pop_rank, c_rat_rank and c_average
CREATE OR REPLACE FUNCTION update_vnvotestats() RETURNS void AS $$
  WITH votes(vid, uid, vote) AS ( -- List of all non-ignored VN votes
    SELECT vid, uid, vote FROM ulist_vns WHERE vote IS NOT NULL AND uid NOT IN(SELECT id FROM users WHERE ign_votes)
  ), avgcount(avgcount) AS ( -- Average number of votes per VN
    SELECT COUNT(vote)::real/COUNT(DISTINCT vid)::real FROM votes
  ), avgavg(avgavg) AS ( -- Average vote average
    SELECT AVG(a)::real FROM (SELECT AVG(vote) FROM votes GROUP BY vid) x(a)
  ), ratings(vid, count, average, rating) AS ( -- Ratings and vote counts
    SELECT vid, COALESCE(COUNT(uid), 0), (AVG(vote)*10)::smallint,
           COALESCE(
              ((SELECT avgcount FROM avgcount) * (SELECT avgavg FROM avgavg) + SUM(vote)::real) /
              ((SELECT avgcount FROM avgcount) + COUNT(uid)::real),
           0)
      FROM votes
     GROUP BY vid
  ), popularities(vid, win) AS ( -- Popularity scores (before normalization)
    SELECT vid, SUM(rank)
      FROM (
        SELECT uid, vid, ((rank() OVER (PARTITION BY uid ORDER BY vote))::real - 1) ^ 0.36788 FROM votes
      ) x(uid, vid, rank)
     GROUP BY vid
  ), stats(vid, rating, count, average, popularity, pop_rank, rat_rank) AS ( -- Combined stats
    SELECT v.id, (r.rating*10)::smallint, COALESCE(r.count, 0), r.average
         , COALESCE((p.win/(SELECT MAX(win) FROM popularities)*10000)::smallint, 0)
         , rank() OVER(ORDER BY hidden, p.win DESC NULLS LAST)
         , CASE WHEN r.rating IS NULL THEN NULL ELSE rank() OVER(ORDER BY hidden, r.rating DESC NULLS LAST) END
      FROM vn v
      LEFT JOIN ratings r ON r.vid = v.id
      LEFT JOIN popularities p ON p.vid = v.id AND p.win > 0
  )
  UPDATE vn SET c_rating = rating, c_votecount = count, c_popularity = popularity, c_pop_rank = pop_rank, c_rat_rank = rat_rank, c_average = average
    FROM stats
   WHERE id = vid AND (c_rating, c_votecount, c_popularity, c_pop_rank, c_rat_rank, c_average) IS DISTINCT FROM (rating, count, popularity, pop_rank, rat_rank, average);
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
      SELECT s.*,
             CASE WHEN EXISTS(
                          SELECT 1 FROM vn v                                        WHERE s.id BETWEEN 'cv1' AND vndbid_max('cv') AND NOT v.hidden AND v.image = s.id
                UNION ALL SELECT 1 FROM vn_screenshots vs JOIN vn v ON v.id = vs.id WHERE s.id BETWEEN 'sf1' AND vndbid_max('sf') AND NOT v.hidden AND vs.scr = s.id
                UNION ALL SELECT 1 FROM chars c                                     WHERE s.id BETWEEN 'ch1' AND vndbid_max('ch') AND NOT c.hidden AND c.image = s.id
             )
             THEN ceil(pow(2, greatest(0, 14 - s.votecount)) + coalesce(pow(s.sexual_stddev, 2), 0)*100 + coalesce(pow(s.violence_stddev, 2), 0)*100)::real
             ELSE 0 END AS weight
        FROM (
            SELECT i.id, count(iv.id) AS votecount
                 , round(avg(sexual)   FILTER(WHERE NOT iv.ignore), 2)::real AS sexual_avg
                 , round(avg(violence) FILTER(WHERE NOT iv.ignore), 2)::real AS violence_avg
                 , round(stddev_pop(sexual)   FILTER(WHERE NOT iv.ignore), 2)::real AS sexual_stddev
                 , round(stddev_pop(violence) FILTER(WHERE NOT iv.ignore), 2)::real AS violence_stddev
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
         , COUNT(DISTINCT uvl.vid) FILTER (WHERE NOT ul.private AND uv.vote IS NOT NULL) -- Voted
         , COUNT(DISTINCT uvl.vid) FILTER (WHERE NOT ul.private AND ul.id NOT IN(5,6)) -- Labelled, but not wishlish/blacklist
         , COUNT(DISTINCT uvl.vid) FILTER (WHERE NOT ul.private AND ul.id = 5) -- Wishlist
      FROM users u
      LEFT JOIN ulist_vns_labels uvl ON uvl.uid = u.id
      LEFT JOIN ulist_labels ul ON ul.id = uvl.lbl AND ul.uid = u.id
      LEFT JOIN ulist_vns uv ON uv.uid = u.id AND uv.vid = uvl.vid
     WHERE $1 IS NULL OR u.id = $1
     GROUP BY u.id
  ) UPDATE users SET c_votes = votes, c_vns = vns, c_wish = wish
      FROM cnt WHERE id = uid AND (c_votes, c_vns, c_wish) IS DISTINCT FROM (votes, vns, wish);
END;
$$ LANGUAGE plpgsql; -- Don't use "LANGUAGE SQL" here; Make sure to generate a new query plan at invocation time.



-- Recalculate tags_vn_direct & tags_vn_inherit.
-- When a vid is given, only the tags for that vid will be updated. These
-- incremental updates do not affect tags.c_items, so that may still get
-- out-of-sync.
CREATE OR REPLACE FUNCTION tag_vn_calc(uvid vndbid) RETURNS void AS $$
BEGIN
  IF uvid IS NULL THEN
    DROP INDEX IF EXISTS tags_vn_direct_tag_vid;
    DROP INDEX IF EXISTS tags_vn_direct_vid;
    TRUNCATE tags_vn_direct;
  ELSE
    DELETE FROM tags_vn_direct WHERE vid = uvid;
  END IF;

  INSERT INTO tags_vn_direct (tag, vid, rating, spoiler, lie)
    SELECT tv.tag, tv.vid, avg(tv.vote)
         , CASE WHEN COUNT(spoiler) = 0 THEN MIN(t.defaultspoil) WHEN AVG(spoiler) > 1.3 THEN 2 WHEN AVG(spoiler) > 0.4 THEN 1 ELSE 0 END
         , count(lie) filter(where lie) > 0 AND count(lie) filter (where lie) >= count(lie)>>1
      FROM tags_vn tv
	  JOIN tags t ON t.id = tv.tag
      LEFT JOIN users u ON u.id = tv.uid
     WHERE NOT t.hidden
       AND NOT tv.ignore AND (u.id IS NULL OR u.perm_tag)
       AND vid NOT IN(SELECT id FROM vn WHERE hidden)
       AND (uvid IS NULL OR vid = uvid)
     GROUP BY tv.tag, tv.vid
    HAVING avg(tv.vote) > 0;

  IF uvid IS NULL THEN
    CREATE INDEX tags_vn_direct_tag_vid ON tags_vn_direct (tag, vid);
    CREATE INDEX tags_vn_direct_vid     ON tags_vn_direct (vid);
    DROP INDEX IF EXISTS tags_vn_inherit_tag_vid;
    TRUNCATE tags_vn_inherit;
  ELSE
    DELETE FROM tags_vn_inherit WHERE vid = uvid;
  END IF;

  INSERT INTO tags_vn_inherit (tag, vid, rating, spoiler)
    -- Add parent tags to each row in tags_vn_direct
    WITH RECURSIVE t_all(lvl, tag, vid, vote, spoiler) AS (
        SELECT 15, tag, vid, rating, spoiler
          FROM tags_vn_direct
         WHERE (uvid IS NULL OR vid = uvid)
        UNION ALL
        SELECT ta.lvl-1, tp.parent, ta.vid, ta.vote, ta.spoiler
          FROM t_all ta
          JOIN tags_parents tp ON tp.id = ta.tag
         WHERE ta.lvl > 0
    )
    -- Merge duplicates
    SELECT tag, vid, AVG(vote), MIN(spoiler)
      FROM t_all
     WHERE tag IN(SELECT id FROM tags WHERE searchable)
     GROUP BY tag, vid;

  IF uvid IS NULL THEN
    CREATE INDEX tags_vn_inherit_tag_vid ON tags_vn_inherit (tag, vid);
    UPDATE tags SET c_items = (SELECT COUNT(*) FROM tags_vn_inherit WHERE tag = id);
  END IF;

  RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;



-- Recalculate traits_chars. Pretty much same thing as tag_vn_calc().
CREATE OR REPLACE FUNCTION traits_chars_calc(ucid vndbid) RETURNS void AS $$
BEGIN
  IF ucid IS NULL THEN
    DROP INDEX IF EXISTS traits_chars_tid;
    TRUNCATE traits_chars;
  ELSE
    DELETE FROM traits_chars WHERE cid = ucid;
  END IF;

  INSERT INTO traits_chars (tid, cid, spoil)
    -- all char<->trait links of the latest revisions, including chars inherited from child traits.
    -- (also includes non-searchable traits, because they could have a searchable trait as parent)
    WITH RECURSIVE traits_chars_all(lvl, tid, cid, spoiler) AS (
        SELECT 15, tid, ct.id, spoil
          FROM chars_traits ct
         WHERE id NOT IN(SELECT id from chars WHERE hidden)
           AND (ucid IS NULL OR ct.id = ucid)
           AND NOT EXISTS (SELECT 1 FROM traits t WHERE t.id = ct.tid AND t.hidden)
      UNION ALL
        SELECT lvl-1, tp.parent, tc.cid, tc.spoiler
        FROM traits_chars_all tc
        JOIN traits_parents tp ON tp.id = tc.tid
        JOIN traits t ON t.id = tp.parent
        WHERE NOT t.hidden
          AND tc.lvl > 0
    )
    -- now grouped by (tid, cid), with non-searchable traits filtered out
    SELECT tid, cid
         , (CASE WHEN MIN(spoiler) > 1.3 THEN 2 WHEN MIN(spoiler) > 0.7 THEN 1 ELSE 0 END)::smallint AS spoiler
      FROM traits_chars_all
     WHERE tid IN(SELECT id FROM traits WHERE searchable)
     GROUP BY tid, cid;

  IF ucid IS NULL THEN
    CREATE INDEX traits_chars_tid ON traits_chars (tid);
    UPDATE traits SET c_items = (SELECT COUNT(*) FROM traits_chars WHERE tid = id);
  END IF;
  RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;



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
-- * User title preferences (through the 'vnt' VIEW) are not used for explicit revisions.
-- * Trait names are prefixed with their group name ("Group > Trait"), but only for non-revisions.
--
-- Returned fields:
--   * title    - Main/romanized title.
--                For users this is their username, not displayname.
--   * original - Original/alternative title (if applicable). Used in edit histories
--   * uid      - User who created/initiated this entry. Used in notification listings and reports
--   * hidden   - Whether this entry is 'hidden' or private. Used for the reporting function & framework_ object.
--                For edits this info comes from the revision itself, not the final entry.
--                Interpretation of this field is dependent on the entry type, For most database entries,
--                'hidden' means "partially visible if you know the ID, but not shown in regular listings".
--                For threads it means "totally invisible, does not exist".
--   * locked   - Whether this entry is 'locked'. Used for the framework_ object.
CREATE OR REPLACE FUNCTION item_info(id vndbid, num int) RETURNS TABLE(title text, original text, uid vndbid, hidden boolean, locked boolean) AS $$
BEGIN
  -- x#
  IF $2 IS NULL THEN CASE vndbid_type($1)
    --WHEN 'v' THEN RETURN QUERY SELECT COALESCE(vo.latin, vo.title), CASE WHEN vo.latin IS NULL THEN '' ELSE vo.title END, NULL::vndbid, v.hidden, v.locked
    --                      FROM vn v JOIN vn_titles vo ON vo.id = v.id AND vo.lang = v.olang WHERE v.id = $1;
    WHEN 'v' THEN RETURN QUERY SELECT v.title   ::text, v.alttitle::text,  NULL::vndbid,  v.hidden, v.locked FROM vnt v       WHERE v.id = $1;
    WHEN 'r' THEN RETURN QUERY SELECT r.title   ::text, r.alttitle::text,  NULL::vndbid,  r.hidden, r.locked FROM releasest r WHERE r.id = $1;
    WHEN 'p' THEN RETURN QUERY SELECT p.name    ::text, p.original::text,  NULL::vndbid,  p.hidden, p.locked FROM producers p WHERE p.id = $1;
    WHEN 'c' THEN RETURN QUERY SELECT c.name    ::text, c.original::text,  NULL::vndbid,  c.hidden, c.locked FROM chars c     WHERE c.id = $1;
    WHEN 'd' THEN RETURN QUERY SELECT d.title   ::text, NULL,              NULL::vndbid,  d.hidden, d.locked FROM docs d      WHERE d.id = $1;
    WHEN 'g' THEN RETURN QUERY SELECT g.name    ::text, NULL,              NULL::vndbid,  g.hidden, g.locked FROM tags g      WHERE g.id = $1;
    WHEN 'i' THEN RETURN QUERY SELECT COALESCE(g.name||' > ', '')||i.name, NULL,NULL::vndbid,i.hidden, i.locked FROM traits i LEFT JOIN traits g ON g.id = i.group WHERE i.id = $1;
    WHEN 's' THEN RETURN QUERY SELECT sa.name   ::text, sa.original::text, NULL::vndbid,  s.hidden, s.locked FROM staff s   JOIN staff_alias sa ON sa.aid = s.aid WHERE s.id = $1;
    WHEN 't' THEN RETURN QUERY SELECT t.title   ::text, NULL,              NULL::vndbid,  t.hidden OR t.private, t.locked FROM threads t WHERE t.id = $1;
    WHEN 'w' THEN RETURN QUERY SELECT v.title   ::text, v.alttitle::text,  w.uid, w.c_flagged, w.locked FROM reviews w JOIN vnt v ON v.id = w.vid WHERE w.id = $1;
    WHEN 'u' THEN RETURN QUERY SELECT u.username::text, NULL,              NULL::vndbid,  FALSE,  FALSE  FROM users u WHERE u.id = $1;
  END CASE;
  -- x#.#
  ELSE CASE vndbid_type($1)
    WHEN 'v' THEN RETURN QUERY SELECT COALESCE(vo.latin, vo.title), CASE WHEN vo.latin IS NULL THEN '' ELSE vo.title END, h.requester, h.ihid, h.ilock
                          FROM changes h JOIN vn_hist v ON h.id = v.chid JOIN vn_titles_hist vo ON h.id = vo.chid AND vo.lang = v.olang WHERE h.itemid = $1 AND h.rev = $2;
    WHEN 'r' THEN RETURN QUERY SELECT COALESCE(ro.latin, ro.title), CASE WHEN ro.latin IS NULL THEN '' ELSE ro.title END, h.requester, h.ihid, h.ilock
                          FROM changes h JOIN releases_hist r ON h.id = r.chid JOIN releases_titles_hist ro ON h.id = ro.chid AND ro.lang = r.olang WHERE h.itemid = $1 AND h.rev = $2;
    WHEN 'p' THEN RETURN QUERY SELECT p.name ::text, p.original::text,  h.requester, h.ihid, h.ilock FROM changes h JOIN producers_hist p ON h.id = p.chid WHERE h.itemid = $1 AND h.rev = $2;
    WHEN 'c' THEN RETURN QUERY SELECT c.name ::text, c.original::text,  h.requester, h.ihid, h.ilock FROM changes h JOIN chars_hist c     ON h.id = c.chid WHERE h.itemid = $1 AND h.rev = $2;
    WHEN 'd' THEN RETURN QUERY SELECT d.title::text, NULL,              h.requester, h.ihid, h.ilock FROM changes h JOIN docs_hist d      ON h.id = d.chid WHERE h.itemid = $1 AND h.rev = $2;
    WHEN 'g' THEN RETURN QUERY SELECT g.name ::text, NULL,              h.requester, h.ihid, h.ilock FROM changes h JOIN tags_hist g      ON h.id = g.chid WHERE h.itemid = $1 AND h.rev = $2;
    WHEN 'i' THEN RETURN QUERY SELECT i.name ::text, NULL,              h.requester, h.ihid, h.ilock FROM changes h JOIN traits_hist i    ON h.id = i.chid WHERE h.itemid = $1 AND h.rev = $2;
    WHEN 's' THEN RETURN QUERY SELECT sa.name::text, sa.original::text, h.requester, h.ihid, h.ilock FROM changes h JOIN staff_hist s     ON h.id = s.chid JOIN staff_alias_hist sa ON sa.chid = s.chid AND sa.aid = s.aid WHERE h.itemid = $1 AND h.rev = $2;
    WHEN 't' THEN RETURN QUERY SELECT t.title::text, NULL,              tp.uid, t.hidden OR t.private OR tp.hidden IS NOT NULL, t.locked FROM threads t JOIN threads_posts tp ON tp.tid = t.id WHERE t.id = $1 AND tp.num = $2;
    WHEN 'w' THEN RETURN QUERY SELECT v.title::text, v.alttitle::text,  wp.uid, w.c_flagged OR wp.hidden IS NOT NULL, w.locked FROM reviews w JOIN vnt v ON v.id = w.vid JOIN reviews_posts wp ON wp.id = w.id WHERE w.id = $1 AND wp.num = $2;
  END CASE;
  END IF;
END;
$$ LANGUAGE plpgsql ROWS 1;



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

  -- Update vn.c_search and tags_vn_*
  IF vndbid_type(nitemid) = 'v' THEN
    UPDATE vn SET c_search = search_gen_vn(id) WHERE id = nitemid;
    PERFORM tag_vn_calc(nitemid); -- actually only necessary when the hidden flag is changed
  END IF;

  -- Update vn.c_search when
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
      UPDATE vn SET c_search = search_gen_vn(id) WHERE id IN(SELECT vid FROM releases_vn_hist WHERE chid IN(nchid, xoldchid));
    END IF;
  END IF;

  -- Update releases.c_search
  IF vndbid_type(nitemid) = 'r' THEN
    UPDATE releases SET c_search = search_gen_release(id) WHERE id = nitemid;
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
     AND id = $1 AND passwd = $3
  RETURNING true
$$ LANGUAGE SQL SECURITY DEFINER;


CREATE OR REPLACE FUNCTION user_logout(vndbid, bytea) RETURNS void AS $$
  DELETE FROM sessions WHERE uid = $1 AND token = $2 AND type IN('web','api')
$$ LANGUAGE SQL SECURITY DEFINER;


-- Returns true if the given session token is valid.
-- As a side effect, this also extends the expiration time of web and api sessions.
CREATE OR REPLACE FUNCTION user_isvalidsession(vndbid, bytea, session_type) RETURNS bool AS $$
  UPDATE sessions SET expires = NOW() + '1 month'
   WHERE uid = $1 AND token = $2 AND type = $3 AND $3 IN('web', 'api')
     AND expires < NOW() + '1 month'::interval - '6 hours'::interval;
  SELECT true FROM sessions WHERE uid = $1 AND token = $2 AND type = $3 AND expires > NOW();
$$ LANGUAGE SQL SECURITY DEFINER;


-- Used for duplicate email checks and user-by-email lookup for usermods.
CREATE OR REPLACE FUNCTION user_emailtoid(text) RETURNS SETOF vndbid AS $$
  SELECT id FROM users_shadow WHERE lower(mail) = lower($1)
$$ LANGUAGE SQL SECURITY DEFINER;


-- Create a password reset token. args: email, token. Returns: user id.
-- Doesn't work for usermods, otherwise an attacker could use this function to
-- gain access to all user's emails by obtaining a reset token of a usermod.
-- Ideally Postgres itself would send the user an email so that the application
-- calling this function doesn't even get the token, and thus can't get access
-- to someone's account. But alas, that'd require a separate process.
CREATE OR REPLACE FUNCTION user_resetpass(text, bytea) RETURNS vndbid AS $$
  INSERT INTO sessions (uid, token, expires, type)
    SELECT id, $2, NOW()+'1 week', 'pass' FROM users_shadow
     WHERE lower(mail) = lower($1) AND length($2) = 20 AND NOT perm_usermod
    RETURNING uid
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
    DELETE FROM sessions WHERE uid IN(SELECT id FROM upd)
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
