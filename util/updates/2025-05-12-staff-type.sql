CREATE TYPE staff_type        AS ENUM ('person', 'group', 'company', 'repo');
DROP VIEW staff_aliast CASCADE;
ALTER TABLE staff ADD COLUMN stype staff_type NOT NULL DEFAULT 'person';
ALTER TABLE staff_hist ADD COLUMN stype staff_type NOT NULL DEFAULT 'person';

\i sql/schema.sql
\i sql/func.sql
\i sql/editfunc.sql
\i sql/perms.sql
