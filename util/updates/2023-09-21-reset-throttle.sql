CREATE TABLE reset_throttle (
  ip        inet NOT NULL PRIMARY KEY,
  timeout   timestamptz NOT NULL
);
\i sql/perms.sql
