ALTER TABLE staff
  ADD COLUMN l_egs      integer NOT NULL DEFAULT 0,
  ADD COLUMN l_anison   integer NOT NULL DEFAULT 0;
ALTER TABLE staff_hist
  ADD COLUMN l_egs      integer NOT NULL DEFAULT 0,
  ADD COLUMN l_anison   integer NOT NULL DEFAULT 0;

DROP VIEW staff_aliast CASCADE;
\i sql/schema.sql
\i sql/editfunc.sql
\i sql/func.sql
\i sql/perms.sql
