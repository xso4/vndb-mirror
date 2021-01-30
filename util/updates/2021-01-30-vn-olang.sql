ALTER TABLE vn      ADD COLUMN olang language NOT NULL DEFAULT 'ja';
ALTER TABLE vn_hist ADD COLUMN olang language NOT NULL DEFAULT 'ja';


-- Initial original language: Use c_olang if it only has a single language,
-- fall back to developer's language if there are multiple languages.
-- (Based on the idea from https://vndb.org/t12800.23)
-- There are still ~50 games for which that fails due to the lack of a
-- developer entry, and ~20 games for which we have no releases at all.
-- These will have to be updated manually.
WITH dl(id, lang) AS (
    SELECT rv.vid, MIN(p.lang)
      FROM releases_vn rv
      JOIN releases r ON r.id = rv.id
      JOIN releases_producers rp ON rp.id = rv.id
      JOIN producers p ON p.id = rp.pid
     WHERE NOT p.hidden AND NOT r.hidden AND rp.developer
     GROUP BY rv.vid
), vl(id, hidden, lang) AS (
    SELECT vn.id, vn.hidden, CASE WHEN array_length(vn.c_olang, 1) = 1 THEN vn.c_olang[1] ELSE dl.lang END
      FROM vn
      LEFT JOIN dl ON dl.id = vn.id
) UPDATE vn SET olang = vl.lang FROM vl WHERE vn.id = vl.id AND vl.lang IS NOT NULL;
--) SELECT 'https://vndb.org/v'||id FROM vl WHERE NOT hidden AND lang IS NULL ORDER BY id;

-- Make sure vn_hist is consistent with vn.
WITH ch(id, lang) AS (
    SELECT c.id, v.olang
      FROM changes c
      JOIN vn v ON v.id = c.itemid
     WHERE c.type = 'v'
) UPDATE vn_hist SET olang = ch.lang FROM ch WHERE vn_hist.chid = ch.id;

\i sql/editfunc.sql
\i sql/func.sql
