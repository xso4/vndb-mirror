BEGIN;

CREATE TABLE releases_titles (
  id         vndbid NOT NULL,
  lang       language NOT NULL,
  mtl        boolean NOT NULL DEFAULT false,
  title      text NOT NULL DEFAULT '',
  latin      text,
  PRIMARY KEY(id, lang)
);

CREATE TABLE releases_titles_hist (
  chid       integer NOT NULL,
  lang       language NOT NULL,
  mtl        boolean NOT NULL DEFAULT false,
  title      text NOT NULL DEFAULT '',
  latin      text,
  PRIMARY KEY(chid, lang)
);

-- Fixup some old (deleted) entries that are missing a language field
INSERT INTO releases_lang SELECT rv.id, v.olang, false FROM releases_vn rv JOIN vn v ON v.id = rv.vid WHERE NOT EXISTS(SELECT 1 FROM releases_lang rl WHERE rl.id = rv.id);
INSERT INTO releases_lang_hist SELECT rv.chid, v.olang, false FROM releases_vn_hist rv JOIN vn v ON v.id = rv.vid WHERE NOT EXISTS(SELECT 1 FROM releases_lang_hist rl WHERE rl.chid = rv.chid);

-- Copy the existing titles to every language.
-- TODO: Is this the right solution? Not sure :/
INSERT INTO releases_titles
    SELECT rl.id, rl.lang, rl.mtl
         , CASE WHEN r.original = '' THEN r.title ELSE r.original END
         , CASE WHEN r.original = '' THEN NULL ELSE r.title END
      FROM releases_lang rl
      JOIN releases r ON r.id = rl.id;

INSERT INTO releases_titles_hist
    SELECT rl.chid, rl.lang, rl.mtl
         , CASE WHEN r.original = '' THEN r.title ELSE r.original END
         , CASE WHEN r.original = '' THEN NULL ELSE r.title END
      FROM releases_lang_hist rl
      JOIN releases_hist r ON r.chid = rl.chid;

ALTER TABLE releases      ADD COLUMN olang language NOT NULL DEFAULT 'ja';
ALTER TABLE releases_hist ADD COLUMN olang language NOT NULL DEFAULT 'ja';

-- 'releases' table needs an olang field now in order to select the proper
-- default title to display. Inherit these from the related (lowest-id) VN
-- entry if the release language matches, otherwise select an arbitrary one
-- (preferring English).
WITH rl (id, ol) AS (
    SELECT DISTINCT ON(rv.id) rv.id, COALESCE(rl.lang, re.lang, rf.lang, v.olang)
      FROM releases_vn rv
      JOIN vn v ON v.id = rv.vid
      LEFT JOIN releases_lang rl ON rl.id = rv.id AND rl.lang = v.olang
      LEFT JOIN releases_lang re ON re.id = rv.id AND re.lang = 'en'
      LEFT JOIN releases_lang rf ON rf.id = rv.id AND (rf.lang <> v.olang AND rf.lang <> 'en')
     ORDER BY rv.id, rl.id NULLS LAST, rv.vid, rl.lang
) UPDATE releases SET olang = ol FROM rl WHERE releases.id = rl.id AND ol <> 'ja';

WITH rl (id, ol) AS (
    SELECT DISTINCT ON(rv.chid) rv.chid, COALESCE(rl.lang, re.lang, rf.lang, v.olang)
      FROM releases_vn_hist rv
      JOIN vn v ON v.id = rv.vid
      LEFT JOIN releases_lang_hist rl ON rl.chid = rv.chid AND rl.lang = v.olang
      LEFT JOIN releases_lang_hist re ON re.chid = rv.chid AND re.lang = 'en'
      LEFT JOIN releases_lang_hist rf ON rf.chid = rv.chid AND (rf.lang <> v.olang AND rf.lang <> 'en')
     ORDER BY rv.chid, rl.chid NULLS LAST, rv.vid, rl.lang
) UPDATE releases_hist SET olang = ol FROM rl WHERE chid = id AND ol <> 'ja';

ALTER TABLE releases ALTER COLUMN c_search DROP NOT NULL, ALTER COLUMN c_search DROP EXPRESSION;

ALTER TABLE releases      DROP COLUMN title, DROP COLUMN original;
ALTER TABLE releases_hist DROP COLUMN title, DROP COLUMN original;

CREATE VIEW releasest AS SELECT r.*, COALESCE(ro.latin, ro.title) AS title, COALESCE(ro.latin, ro.title) AS sorttitle, CASE WHEN ro.latin IS NULL THEN '' ELSE ro.title END AS alttitle FROM releases r JOIN releases_titles ro ON ro.id = r.id AND ro.lang = r.olang;

DROP TABLE releases_lang, releases_lang_hist;

COMMIT;

\i sql/tableattrs.sql
\i sql/func.sql
\i sql/editfunc.sql
\i sql/perms.sql
