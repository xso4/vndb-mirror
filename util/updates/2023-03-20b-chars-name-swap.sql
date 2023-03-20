ALTER TABLE chars      RENAME COLUMN original TO latin;
ALTER TABLE chars_hist RENAME COLUMN original TO latin;

UPDATE chars      SET name = latin, latin = name WHERE latin IS NOT NULL;
UPDATE chars_hist SET name = latin, latin = name WHERE latin IS NOT NULL;

DROP VIEW charst CASCADE;

\i sql/schema.sql
\i sql/editfunc.sql
\i sql/func.sql
\i sql/perms.sql
