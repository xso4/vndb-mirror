DROP VIEW vnt CASCADE;

ALTER TABLE vn ADD COLUMN c_moe boolean NOT NULL DEFAULT false;

\i sql/schema.sql
\i sql/perms.sql
\i sql/func.sql

\timing
select update_vncache(null);
