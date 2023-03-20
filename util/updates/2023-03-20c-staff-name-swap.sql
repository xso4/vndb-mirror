ALTER TABLE staff_alias      RENAME COLUMN original TO latin;
ALTER TABLE staff_alias_hist RENAME COLUMN original TO latin;

UPDATE staff_alias      SET name = latin, latin = name WHERE latin IS NOT NULL;
UPDATE staff_alias_hist SET name = latin, latin = name WHERE latin IS NOT NULL;

DROP VIEW staff_aliast CASCADE;

\i sql/schema.sql
\i sql/editfunc.sql
\i sql/func.sql
\i sql/perms.sql

DROP FUNCTION titleprefs_swapold(titleprefs, language, text, text);
