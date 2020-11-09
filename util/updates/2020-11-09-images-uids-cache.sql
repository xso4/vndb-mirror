ALTER TABLE images ADD COLUMN c_uids integer[] NOT NULL DEFAULT '{}';

\i sql/func.sql

SELECT update_images_cache(null);
