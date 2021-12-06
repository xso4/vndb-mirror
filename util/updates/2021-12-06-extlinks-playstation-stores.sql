ALTER TABLE releases
  ADD COLUMN l_playstation_jp text NOT NULL DEFAULT '',
  ADD COLUMN l_playstation_na text NOT NULL DEFAULT '',
  ADD COLUMN l_playstation_eu text NOT NULL DEFAULT '';
ALTER TABLE releases_hist
  ADD COLUMN l_playstation_jp text NOT NULL DEFAULT '',
  ADD COLUMN l_playstation_na text NOT NULL DEFAULT '',
  ADD COLUMN l_playstation_eu text NOT NULL DEFAULT '';
ALTER TABLE wikidata
  ADD COLUMN playstation_jp text[],
  ADD COLUMN playstation_na text[],
  ADD COLUMN playstation_eu text[];
\i sql/editfunc.sql
