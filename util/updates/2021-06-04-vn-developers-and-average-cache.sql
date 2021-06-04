ALTER TABLE users ADD COLUMN tableopts_v         integer;
ALTER TABLE users ADD COLUMN tableopts_vt        integer;

ALTER TABLE vn ADD COLUMN c_developers  vndbid[] NOT NULL DEFAULT '{}';
ALTER TABLE vn ADD COLUMN c_average     smallint;
ALTER TABLE vn ALTER COLUMN c_popularity TYPE smallint USING c_popularity*10000;
ALTER TABLE vn ALTER COLUMN c_rating     TYPE smallint USING c_rating*10;
\i sql/func.sql
\timing
SELECT count(*) FROM (SELECT update_vncache(id) FROM vn) x;
SELECT update_vnvotestats();
