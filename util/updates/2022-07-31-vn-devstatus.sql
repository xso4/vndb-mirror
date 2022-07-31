ALTER TABLE vn      ADD COLUMN devstatus    smallint NOT NULL DEFAULT 0;
ALTER TABLE vn_hist ADD COLUMN devstatus    smallint NOT NULL DEFAULT 0;
\i sql/editfunc.sql

UPDATE vn SET devstatus = 0 WHERE devstatus <> 0;

-- Heuristic: VN is considered cancelled if it meets all of the following criteria:
-- * doesn't have a complete release
-- * doesn't have any release after 2020
-- * doesn't have multiple partial releases
-- * doesn't have both a trial and partial release (weird heuristic, but there's many matching in-dev games)
UPDATE vn SET devstatus = 2 WHERE
      id NOT IN(SELECT vid FROM releases_vn rv JOIN releases r ON r.id = rv.id WHERE NOT r.hidden AND rtype = 'complete' OR released > 20200000)
  AND id NOT IN(SELECT vid FROM releases_vn rv JOIN releases r ON r.id = rv.id WHERE NOT r.hidden AND rtype = 'partial' GROUP BY vid HAVING COUNT(r.id) > 1)
  AND id NOT IN(SELECT vid FROM releases_vn rv JOIN releases r ON r.id = rv.id WHERE NOT r.hidden AND rtype IN('partial','trial') GROUP BY vid HAVING COUNT(DISTINCT rtype) = 2);

-- Heuristic: VN is considerd in development if it's not cancelled and meets one of the following:
-- * Has a future release date
-- * Has no complete releases and only a single partial release
UPDATE vn SET devstatus = 1 WHERE devstatus = 0 AND (c_released > 22020731 OR (
         id NOT IN(SELECT vid FROM releases_vn rv JOIN releases r ON r.id = rv.id WHERE NOT r.hidden AND rtype = 'complete')
     AND id     IN(SELECT vid FROM releases_vn rv JOIN releases r ON r.id = rv.id WHERE NOT r.hidden AND rtype = 'partial' GROUP BY vid HAVING COUNT(r.id) = 1)));

UPDATE vn_hist SET devstatus = v.devstatus FROM changes c JOIN vn v ON c.itemid = v.id WHERE vn_hist.chid = c.id AND v.devstatus <> vn_hist.devstatus;
