ALTER TABLE releases
    ADD COLUMN l_patreonp integer NOT NULL DEFAULT 0,
    ADD COLUMN l_patreon  text NOT NULL DEFAULT '',
    ADD COLUMN l_substar  text NOT NULL DEFAULT '';
ALTER TABLE releases_hist
    ADD COLUMN l_patreonp integer NOT NULL DEFAULT 0,
    ADD COLUMN l_patreon  text NOT NULL DEFAULT '',
    ADD COLUMN l_substar  text NOT NULL DEFAULT '';
\i sql/editfunc.sql

DROP VIEW releasest CASCADE;
\i sql/schema.sql
\i sql/func.sql
\i sql/perms.sql



-- patreonp from website field
CREATE OR REPLACE FUNCTION migrate_website_to_patreonp(rid vndbid) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid));
    UPDATE edit_releases SET l_patreonp = regexp_replace(website, '^https?://(?:www\.)?patreon\.com/posts/(?:[^/?]+-)?([0-9]+).*$', '\1')::int, website = '';
    UPDATE edit_revision SET requester = 'u1', comments = 'Automatic conversion of website to Patreon link.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;
SELECT count(*) FROM (SELECT migrate_website_to_patreonp(id) FROM releases WHERE NOT hidden AND website ~ '^https?://(?:www\.)?patreon\.com/posts/(?:[^/?]+-)?([0-9]+)') x;
DROP FUNCTION migrate_website_to_patreonp(vndbid);



-- patreon from website field
CREATE OR REPLACE FUNCTION migrate_website_to_patreon(rid vndbid) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid));
    UPDATE edit_releases SET l_patreon = regexp_replace(website, '^https?://(?:www\.)?patreon\.com/(?!user[\?/]|posts[\?/]|join[\?/])([^/?]+).*$', '\1'), website = '';
    UPDATE edit_revision SET requester = 'u1', comments = 'Automatic conversion of website to Patreon link.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;
SELECT count(*) FROM (SELECT migrate_website_to_patreon(id) FROM releases WHERE NOT hidden AND website ~ '^https?://(?:www\.)?patreon\.com/(?!user[\?/]|posts[\?/]|join[\?/])([^/?]+)') x;
DROP FUNCTION migrate_website_to_patreon(vndbid);




-- patreon from notes field
CREATE OR REPLACE FUNCTION migrate_notes_to_patreon(rid vndbid) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid));
    UPDATE edit_releases SET
        l_patreon = regexp_replace(notes, '^.*\s*(?:Also available|Were only available|Only available|Available) (?:on|at|from) \[url=https?://(?:www\.)?patreon\.com/(?!user[\?/]|posts[\?/]|join[\?/])([^/?]+)[^\]]*\][^\[]+\[/url\](?:\,?$|\.\s*).*$', '\1', 'i'),
        notes = regexp_replace(notes, '\s*(?:Also available|Were only available|Only available|Available) (?:on|at|from) \[url=https?://(?:www\.)?patreon\.com/(?!user[\?/]|posts[\?/]|join[\?/])([^/?]+)[^\]]*\][^\[]+\[/url\](?:\,?$|\.\s*)', '', 'i');
    UPDATE edit_revision SET requester = 'u1', comments = 'Automatic extraction of Patreon link from the notes.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;
SELECT count(*) FROM (SELECT migrate_notes_to_patreon(id) FROM releases WHERE NOT hidden AND l_patreon = ''
    AND notes ~* '\s*(?:Also available|Were only available|Only available|Available) (?:on|at|from) \[url=https?://(?:www\.)?patreon\.com/(?!user[\?/]|posts[\?/]|join[\?/])([^/?]+)[^\]]*\][^\[]+\[/url\](?:\,?$|\.\s*)'
    AND id NOT IN('r55516', 'r54903', 'r50178')
) x;
DROP FUNCTION migrate_notes_to_patreon(vndbid);




-- substar from website field
CREATE OR REPLACE FUNCTION migrate_website_to_substar(rid vndbid) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid));
    UPDATE edit_releases SET l_substar = regexp_replace(website, '^https?://(?:www\.)?subscribestar\.((?:adult|com)/[^/?]+).*$', '\1'), website = '';
    UPDATE edit_revision SET requester = 'u1', comments = 'Automatic conversion of website to SubscribeStar link.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;
SELECT count(*) FROM (SELECT migrate_website_to_substar(id) FROM releases WHERE NOT hidden AND website ~ '^https?://(?:www\.)?subscribestar\.((?:adult|com)/[^/?]+)') x;
DROP FUNCTION migrate_website_to_substar(vndbid);




-- substar from notes field
CREATE OR REPLACE FUNCTION migrate_notes_to_substar(rid vndbid) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid));
    UPDATE edit_releases SET
        l_substar = regexp_replace(notes, '^.*\s*(?:Also available|Were only available|Only available|Available) (?:on|at|from) \[url=https?://(?:www\.)?subscribestar\.((?:adult|com)/[^/?]+)[^\]]*\][^\[]+\[/url\](?:\,?$|\.\s*).*$', '\1', 'i'),
        notes = regexp_replace(notes, '\s*(?:Also available|Were only available|Only available|Available) (?:on|at|from) \[url=https?://(?:www\.)?subscribestar\.((?:adult|com)/[^/?]+)[^\]]*\][^\[]+\[/url\](?:\,?$|\.\s*)', '', 'i');
    UPDATE edit_revision SET requester = 'u1', comments = 'Automatic extraction of SubscribeStar link from the notes.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;
SELECT count(*) FROM (SELECT migrate_notes_to_substar(id) FROM releases WHERE NOT hidden AND l_substar = ''
    AND notes ~* '\s*(?:Also available|Were only available|Only available|Available) (?:on|at|from) \[url=https?://(?:www\.)?subscribestar\.((?:adult|com)/[^/?]+)[^\]]*\][^\[]+\[/url\](?:\,?$|\.\s*)'
) x;
DROP FUNCTION migrate_notes_to_substar(vndbid);



--select 'https://vndb.org/'||id, title[2], website from releasest where not hidden and website like 'https://www.patreon.com%' order by id;
--select 'https://vndb.org/'||id, title[2] from releasest where not hidden and notes like '%https://www.patreon.com%' order by id;
--select 'https://vndb.org/'||id, title[2] from releasest where not hidden and notes like '%subscribestar%' order by id;
