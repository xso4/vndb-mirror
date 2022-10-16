ALTER TABLE releases
  ADD COLUMN l_nintendo_jp bigint NOT NULL DEFAULT 0,
  ADD COLUMN l_nintendo_hk bigint NOT NULL DEFAULT 0,
  ADD COLUMN l_nintendo    text NOT NULL DEFAULT '',
  ADD COLUMN l_playstation_hk text NOT NULL DEFAULT '';
ALTER TABLE releases_hist
  ADD COLUMN l_nintendo_jp bigint NOT NULL DEFAULT 0,
  ADD COLUMN l_nintendo_hk bigint NOT NULL DEFAULT 0,
  ADD COLUMN l_nintendo    text NOT NULL DEFAULT '',
  ADD COLUMN l_playstation_hk text NOT NULL DEFAULT '';
\i sql/editfunc.sql
