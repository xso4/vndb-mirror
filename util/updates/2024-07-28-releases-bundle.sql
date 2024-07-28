DROP VIEW releasest CASCADE;
ALTER TABLE releases ADD COLUMN c_bundle     boolean NOT NULL DEFAULT false;
\i sql/schema.sql
\i sql/func.sql
\i sql/perms.sql

UPDATE releases SET c_bundle = true WHERE id IN(SELECT id FROM releases_vn GROUP BY id HAVING COUNT(vid) > 1);
