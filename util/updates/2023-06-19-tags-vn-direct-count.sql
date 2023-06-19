ALTER TABLE tags_vn_direct ADD COLUMN count smallint NOT NULL DEFAULT 0;
\i sql/func.sql
SELECT tag_vn_calc(NULL);
ALTER TABLE tags_vn_direct ALTER COLUMN count DROP DEFAULT;
