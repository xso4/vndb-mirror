ALTER TABLE extlinks
  ADD COLUMN redirect     boolean NOT NULL DEFAULT FALSE,
  ADD COLUMN unrecognized boolean NOT NULL DEFAULT FALSE,
  ADD COLUMN serverror    boolean NOT NULL DEFAULT FALSE;

UPDATE extlinks SET redirect     = true WHERE id IN(SELECT id FROM (SELECT DISTINCT ON (id) id, first_value(detail) OVER (PARTITION BY id ORDER BY date DESC) FROM extlinks_fetch) x(id,detail) WHERE json_exists(detail, '$.location'));
UPDATE extlinks SET unrecognized = true WHERE id IN(SELECT id FROM (SELECT DISTINCT ON (id) id, first_value(detail) OVER (PARTITION BY id ORDER BY date DESC) FROM extlinks_fetch) x(id,detail) WHERE json_exists(detail, '$.unrecognized'));
UPDATE extlinks SET serverror    = true WHERE id IN(SELECT id FROM (SELECT DISTINCT ON (id) id, first_value(detail) OVER (PARTITION BY id ORDER BY date DESC) FROM extlinks_fetch) x(id,detail) WHERE json_exists(detail, '$.code ? (@.integer() >= 500)'));
