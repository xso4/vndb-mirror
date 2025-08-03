DROP TRIGGER anime_fetch_notify ON anime;
DROP FUNCTION anime_fetch_notify();

ALTER TABLE anime DROP COLUMN nfo_id;
ALTER TABLE anime ALTER COLUMN ann_id TYPE integer[] USING CASE WHEN ann_id IS NULL THEN NULL ELSE ARRAY[ann_id] END;
ALTER TABLE anime ADD COLUMN mal_id integer[];

\i sql/triggers.sql
