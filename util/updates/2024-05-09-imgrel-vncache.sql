ALTER TABLE vn ADD COLUMN c_imgfirst vndbid;
ALTER TABLE vn ADD COLUMN c_imglast vndbid;
ALTER TABLE users_prefs ADD COLUMN vnimage smallint NOT NULL DEFAULT 0;

DROP VIEW vnt CASCADE;
\i sql/schema.sql
\i sql/perms.sql

\i sql/func.sql
SELECT update_vncache(NULL);

