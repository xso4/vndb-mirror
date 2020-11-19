ALTER TABLE releases      ADD COLUMN official   boolean NOT NULL DEFAULT TRUE;
ALTER TABLE releases_hist ADD COLUMN official   boolean NOT NULL DEFAULT TRUE;

\i sql/editfunc.sql

-- A release is considered unofficial if it was published by an individual or
-- amateur group while the original developer is a company.
-- This should not have many false positives, but only covers a small part of the DB.
UPDATE releases r SET official = FALSE
 WHERE EXISTS(SELECT 1
        FROM releases_vn rv
        JOIN releases_vn rv2 ON rv.vid = rv2.vid
        JOIN releases r2 ON r2.id = rv2.id
        JOIN releases_producers rp2 ON rp2.id = rv2.id
        JOIN producers p ON p.id = rp2.pid
       WHERE NOT p.hidden AND NOT r2.hidden AND rp2.developer AND rv.id = r.id AND p.type = 'co')
  AND NOT EXISTS(SELECT 1 FROM releases_producers rp JOIN producers p ON p.id = rp.pid WHERE rp.id = r.id AND (rp.developer OR p.type = 'co'));

UPDATE releases_hist rh SET official = FALSE
 WHERE EXISTS(SELECT 1 FROM changes c JOIN releases r ON r.id = c.itemid WHERE c.id = rh.chid AND NOT r.official);
