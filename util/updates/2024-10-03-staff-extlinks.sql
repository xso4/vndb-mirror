ALTER TABLE staff
  ADD COLUMN l_patreon   text NOT NULL DEFAULT '',
  ADD COLUMN l_substar   text NOT NULL DEFAULT '',
  ADD COLUMN l_youtube   text NOT NULL DEFAULT '',
  ADD COLUMN l_instagram text NOT NULL DEFAULT '',
  ADD COLUMN l_deviantar text NOT NULL DEFAULT '',
  ADD COLUMN l_tumblr    text NOT NULL DEFAULT '';
ALTER TABLE staff_hist
  ADD COLUMN l_patreon   text NOT NULL DEFAULT '',
  ADD COLUMN l_substar   text NOT NULL DEFAULT '',
  ADD COLUMN l_youtube   text NOT NULL DEFAULT '',
  ADD COLUMN l_instagram text NOT NULL DEFAULT '',
  ADD COLUMN l_deviantar text NOT NULL DEFAULT '',
  ADD COLUMN l_tumblr    text NOT NULL DEFAULT '';

DROP VIEW staff_aliast CASCADE;
\i sql/schema.sql
\i sql/editfunc.sql
\i sql/func.sql
\i sql/perms.sql
