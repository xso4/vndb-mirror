ALTER TABLE users_shadow ADD COLUMN delete_at timestamptz;

\i sql/func.sql
\i sql/perms.sql
