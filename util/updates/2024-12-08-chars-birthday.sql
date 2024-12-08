DROP VIEW charst CASCADE;

BEGIN;
ALTER TABLE chars RENAME COLUMN b_month TO birthday;
UPDATE chars SET birthday = birthday * 100 + b_day;
ALTER TABLE chars DROP COLUMN b_day;

ALTER TABLE chars_hist RENAME COLUMN b_month TO birthday;
UPDATE chars_hist SET birthday = birthday * 100 + b_day;
ALTER TABLE chars_hist DROP COLUMN b_day;
COMMIT;

\i sql/schema.sql
\i sql/editfunc.sql
\i sql/func.sql
\i sql/perms.sql
