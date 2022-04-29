-- NOTE: Make sure you're cd'ed in the vndb root directory before running this script

\set ON_ERROR_STOP 1
\i sql/util.sql
\i sql/schema.sql
\i sql/data.sql
\i sql/func.sql
\i sql/editfunc.sql
\i sql/tableattrs.sql
\i sql/triggers.sql
\set ON_ERROR_STOP 0
\i sql/perms.sql
