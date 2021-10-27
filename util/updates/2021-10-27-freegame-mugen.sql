ALTER TABLE releases      ADD COLUMN l_freegame   text NOT NULL DEFAULT '';
ALTER TABLE releases_hist ADD COLUMN l_freegame   text NOT NULL DEFAULT '';
\i sql/editfunc.sql
