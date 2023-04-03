ALTER TABLE releases      ADD COLUMN l_booth integer NOT NULL DEFAULT 0;
ALTER TABLE releases_hist ADD COLUMN l_booth integer NOT NULL DEFAULT 0;
\i sql/editfunc.sql

DROP VIEW releasest CASCADE;
\i sql/schema.sql
\i sql/func.sql
\i sql/perms.sql


-- Extract from website field
CREATE OR REPLACE FUNCTION migrate_website_to_booth(rid vndbid) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid));
    UPDATE edit_releases SET l_booth = regexp_replace(website, '^https?://(?:[a-z0-9_-]+\.)?booth\.pm/(?:[a-z-]+\/)?items/([0-9]+).*', '\1')::int, website = '';
    UPDATE edit_revision SET requester = 'u1', comments = 'Automatic conversion of website to BOOTH link.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;
SELECT migrate_website_to_booth(id) FROM releases WHERE NOT hidden AND website ~ '^https?://(?:[a-z0-9_-]+\.)?booth\.pm/(?:[a-z-]+\/)?items/([0-9]+)';
DROP FUNCTION migrate_website_to_booth(vndbid);



-- Extract from notes in "Available at .." format
CREATE OR REPLACE FUNCTION migrate_notes_to_booth(rid vndbid) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid));
    UPDATE edit_releases SET
        l_booth = regexp_replace(notes, '^.*\s*(?:Also available|Available) (?:on|at|from) \[url=https?://(?:[a-z0-9_-]+\.)?booth\.pm/(?:[a-z-]+\/)?items/([0-9]+)[^\]]*\][^\[]+\[/url\](?:\,?$|\.\s*).*$', '\1', 'i')::int,
        notes = regexp_replace(notes, '\s*(?:Also available|Available) (?:on|at|from) \[url=https?://(?:[a-z0-9_-]+\.)?booth\.pm/(?:[a-z-]+\/)?items/([0-9]+)[^\]]*\][^\[]+\[/url\](?:\,?$|\.\s*)', '', 'i');
    UPDATE edit_revision SET requester = 'u1', comments = 'Automatic extraction of BOOTH link from the notes.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;
SELECT migrate_notes_to_booth(id) FROM releases WHERE NOT hidden AND l_booth = 0
    AND notes ~* '\s*(?:Also available|Available) (?:on|at|from) \[url=https?://(?:[a-z0-9_-]+\.)?booth\.pm/(?:[a-z-]+\/)?items/([0-9]+)[^\]]*\][^\[]+\[/url\](?:\,?$|\.\s*)'
    AND id <> 'r104675';
DROP FUNCTION migrate_notes_to_booth(vndbid);



-- Extract from notes when it's the only thing in the note
CREATE OR REPLACE FUNCTION migrate_notes_to_booth2(rid vndbid) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid));
    UPDATE edit_releases SET l_booth = regexp_replace(notes, '^(?:booth|available on)?:?\s*(?:\[url=)?https?://(?:[a-z0-9_-]+\.)?booth\.pm/(?:[a-z-]+\/)?items/([0-9]+)(?:\][^\[]*\[/url\])?\.?$', '\1', 'i')::int, notes = '';
    UPDATE edit_revision SET requester = 'u1', comments = 'Automatic extraction of BOOTH link from the notes.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;
SELECT migrate_notes_to_booth2(id) FROM releases WHERE NOT hidden AND l_booth = 0
    AND notes ~* '^(?:booth|available on)?:?\s*(?:\[url=)?https?://(?:[a-z0-9_-]+\.)?booth\.pm/(?:[a-z-]+\/)?items/([0-9]+)(?:\][^\[]*\[/url\])?\.?$';
DROP FUNCTION migrate_notes_to_booth2(vndbid);


-- select 'https://vndb.org/'||id, title[2] from releasest where not hidden and notes like '%booth.pm%' order by id;
