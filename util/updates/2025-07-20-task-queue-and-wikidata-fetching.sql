DROP FUNCTION user_delete();

UPDATE extlinks SET lastfetch = w.lastfetch FROM wikidata w WHERE site = 'wikidata' AND value = w.id::text;

\i sql/util.sql
\i sql/schema.sql
\i sql/tableattrs.sql

ALTER TABLE wikidata DROP COLUMN lastfetch;
DROP TRIGGER extlinks_wikidata_new ON extlinks;
DROP FUNCTION wikidata_extlink_insert();
