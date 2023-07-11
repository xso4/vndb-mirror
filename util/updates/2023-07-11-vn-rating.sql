DROP VIEW vnt CASCADE;
ALTER TABLE vn DROP COLUMN c_popularity;
\i sql/schema.sql
\i sql/func.sql
\i sql/perms.sql
-- Twice, to stabilize the "top50" variable.
SELECT update_vnvotestats();
SELECT update_vnvotestats();
