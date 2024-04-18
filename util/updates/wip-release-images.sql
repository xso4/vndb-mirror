DROP VIEW vnt CASCADE;
ALTER TABLE vn ADD COLUMN c_image vndbid;
UPDATE vn SET c_image = image;

\i sql/schema.sql
\i sql/tableattrs.sql
\i sql/func.sql
\i sql/editfunc.sql
\i sql/perms.sql
