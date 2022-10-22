ALTER TABLE tags_vn_inherit ADD COLUMN lie boolean;
\i sql/func.sql
SELECT tag_vn_calc(null);
ALTER TABLE tags_vn_inherit ALTER COLUMN lie DROP NOT NULL;
