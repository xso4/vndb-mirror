ALTER TABLE producers      RENAME COLUMN original TO latin;
ALTER TABLE producers_hist RENAME COLUMN original TO latin;

UPDATE producers      SET name = latin, latin = name WHERE latin IS NOT NULL;
UPDATE producers_hist SET name = latin, latin = name WHERE latin IS NOT NULL;

DROP FUNCTION titleprefs_swap(titleprefs, language, text, text);
DROP VIEW producerst CASCADE;

\i sql/schema.sql
\i sql/editfunc.sql
\i sql/func.sql
\i sql/perms.sql
