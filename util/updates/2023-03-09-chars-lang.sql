ALTER TABLE chars ADD COLUMN c_lang language NOT NULL DEFAULT 'ja';

WITH x(id,lang) AS (
  SELECT DISTINCT ON (cv.id) cv.id, v.olang
    FROM chars_vns cv
    JOIN vn v ON v.id = cv.vid
   ORDER BY cv.id, v.hidden, v.c_released
) UPDATE chars c SET c_lang = x.lang FROM x WHERE c.id = x.id AND c.c_lang <> x.lang;

\i sql/func.sql
