ALTER TABLE releases      ADD COLUMN l_animateg integer NOT NULL DEFAULT 0;
ALTER TABLE releases_hist ADD COLUMN l_animateg integer NOT NULL DEFAULT 0;
ALTER TABLE releases      ADD COLUMN l_freem integer NOT NULL DEFAULT 0;
ALTER TABLE releases_hist ADD COLUMN l_freem integer NOT NULL DEFAULT 0;
-- I don't think I've actually seen app store IDs that didn't fit in an int, but they can get pretty close.
ALTER TABLE releases      ADD COLUMN l_appstore bigint NOT NULL DEFAULT 0;
ALTER TABLE releases_hist ADD COLUMN l_appstore bigint NOT NULL DEFAULT 0;
ALTER TABLE releases      ADD COLUMN l_googplay text NOT NULL DEFAULT '';
ALTER TABLE releases_hist ADD COLUMN l_googplay text NOT NULL DEFAULT '';
\i sql/editfunc.sql


CREATE OR REPLACE FUNCTION migrate_website_to_freem(rid integer) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid AND type = 'r'));
    UPDATE edit_releases SET l_freem = regexp_replace(website, '^https?://(?:www\.)?freem\.ne\.jp/win/game/([0-9]+)$', '\1')::int, website = '';
    UPDATE edit_revision SET requester = 1, ip = '0.0.0.0', comments = 'Automatic conversion of website to Freem link.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;
SELECT migrate_website_to_freem(id) FROM releases WHERE NOT hidden AND website ~ '^https?://(?:www\.)?freem\.ne\.jp/win/game/([0-9]+)$';
DROP FUNCTION migrate_website_to_freem(integer);


CREATE OR REPLACE FUNCTION migrate_website_to_googplay(rid integer) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid AND type = 'r'));
    UPDATE edit_releases SET l_googplay = regexp_replace(website, '^https?://play\.google\.com/store/apps/details\?id=([^/&\?]+)(?:&.*)?$', '\1'), website = '';
    UPDATE edit_revision SET requester = 1, ip = '0.0.0.0', comments = 'Automatic conversion of website to Google Play store link.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;
SELECT migrate_website_to_googplay(id) FROM releases WHERE NOT hidden AND website ~ '^https?://play\.google\.com/store/apps/details\?id=([^/&\?]+)(?:&.*)?$';
DROP FUNCTION migrate_website_to_googplay(integer);


CREATE OR REPLACE FUNCTION migrate_website_to_appstore(rid integer) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid AND type = 'r'));
    UPDATE edit_releases SET l_appstore = regexp_replace(website, '^https?://(?:itunes|apps)\.apple\.com/(?:[^/]+/)?app/(?:[^/]+/)?id([0-9]+)([\?/].*)?$', '\1')::bigint, website = '';
    UPDATE edit_revision SET requester = 1, ip = '0.0.0.0', comments = 'Automatic conversion of website to Apple App Store link.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;
SELECT migrate_website_to_appstore(id) FROM releases WHERE NOT hidden AND website ~ '^https?://(?:itunes|apps)\.apple\.com/(?:[^/]+/)?app/(?:[^/]+/)?id([0-9]+)([\?/].*)?$';
DROP FUNCTION migrate_website_to_appstore(integer);
