BEGIN;
ALTER TABLE releases_vn      ADD COLUMN rtype release_type NOT NULL DEFAULT 'complete';
ALTER TABLE releases_vn_hist ADD COLUMN rtype release_type NOT NULL DEFAULT 'complete';
ALTER TABLE releases_vn      ALTER COLUMN rtype DROP DEFAULT;
ALTER TABLE releases_vn_hist ALTER COLUMN rtype DROP DEFAULT;
UPDATE releases_vn      SET rtype = type FROM releases r      WHERE r.id = releases_vn.id;
UPDATE releases_vn_hist SET rtype = type FROM releases_hist r WHERE r.chid = releases_vn_hist.chid;
ALTER TABLE releases      DROP COLUMN type;
ALTER TABLE releases_hist DROP COLUMN type;
\i sql/editfunc.sql
\i sql/func.sql
COMMIT;
