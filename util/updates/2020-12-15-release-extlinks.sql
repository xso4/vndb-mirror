ALTER TABLE releases      ADD COLUMN l_fakku    text NOT NULL DEFAULT '';
ALTER TABLE releases_hist ADD COLUMN l_fakku    text NOT NULL DEFAULT '';
ALTER TABLE releases      ADD COLUMN l_novelgam integer NOT NULL DEFAULT 0;
ALTER TABLE releases_hist ADD COLUMN l_novelgam integer NOT NULL DEFAULT 0;
\i sql/editfunc.sql

CREATE OR REPLACE FUNCTION migrate_website_to_novelgam(rid integer) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid AND type = 'r'));
    UPDATE edit_releases SET l_novelgam = regexp_replace(website, '^https?://(?:www\.)?novelgame\.jp/games/show/([0-9]+)$', '\1')::int, website = '';
    UPDATE edit_revision SET requester = 1, ip = '0.0.0.0', comments = 'Automatic conversion of website to NovelGame link.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;
SELECT migrate_website_to_novelgam(id) FROM releases WHERE NOT hidden AND website ~ '^https?://(?:www\.)?novelgame\.jp/games/show/([0-9]+)$';
DROP FUNCTION migrate_website_to_novelgam(integer);
