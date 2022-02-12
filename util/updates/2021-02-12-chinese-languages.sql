ALTER TYPE language ADD VALUE 'zh-Hans' AFTER 'zh';
ALTER TYPE language ADD VALUE 'zh-Hant' AFTER 'zh-Hans';


CREATE OR REPLACE FUNCTION migrate_notes_to_lang(rid vndbid, rlang language) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid));
    UPDATE edit_releases_lang SET lang = rlang WHERE lang = 'zh';
    UPDATE edit_releases SET notes = regexp_replace(notes, '\s*(Simplified|Traditional) Chinese\.?\s*', '', 'i');
    UPDATE edit_revision SET requester = 'u1', ip = '0.0.0.0', comments = 'Automatic extraction of Chinese language from the notes.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;

SELECT COUNT(*) FROM (SELECT migrate_notes_to_lang(id, 'zh-Hans')
--SELECT 'http://whatever.blicky.net/'||r.id, regexp_replace(r.notes, '\s*Simplified Chinese\.?\s*', '', 'i')
    FROM releases r WHERE NOT hidden
    AND EXISTS(SELECT 1 FROM releases_lang rl WHERE rl.id = r.id AND rl.lang = 'zh')
    AND NOT EXISTS(SELECT 1 FROM releases_lang rl WHERE rl.id = r.id AND rl.lang IN('zh-Hans', 'zh-Hant'))
    AND notes ~* '(^|\n)Simplified Chinese(\.|\n|$)'
) x;

SELECT COUNT(*) FROM (SELECT migrate_notes_to_lang(id, 'zh-Hant')
    FROM releases r WHERE NOT hidden
    AND EXISTS(SELECT 1 FROM releases_lang rl WHERE rl.id = r.id AND rl.lang = 'zh')
    AND NOT EXISTS(SELECT 1 FROM releases_lang rl WHERE rl.id = r.id AND rl.lang IN('zh-Hans', 'zh-Hant'))
    AND notes ~* '(^|\n)Traditional Chinese(\.|\n|$)'
) x;

DROP FUNCTION migrate_notes_to_lang(vndbid, language);
