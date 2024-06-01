DROP VIEW releasest CASCADE;
ALTER TABLE releases      ALTER COLUMN l_nintendo_jp TYPE text;
ALTER TABLE releases_hist ALTER COLUMN l_nintendo_jp TYPE text;
ALTER TABLE releases      ALTER COLUMN l_nintendo_jp SET DEFAULT '';
ALTER TABLE releases_hist ALTER COLUMN l_nintendo_jp SET DEFAULT '';
UPDATE releases      SET l_nintendo_jp = '' WHERE l_nintendo_jp = '0';
UPDATE releases_hist SET l_nintendo_jp = '' WHERE l_nintendo_jp = '0';
\i sql/schema.sql
