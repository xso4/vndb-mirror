ALTER TABLE vn ADD COLUMN c_length      smallint;
ALTER TABLE vn ADD COLUMN c_lengthnum   smallint NOT NULL DEFAULT 0;

\i sql/func.sql
\i sql/triggers.sql
select update_vn_length_cache(null);
