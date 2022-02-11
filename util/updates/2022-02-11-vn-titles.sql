BEGIN;

CREATE TABLE vn_titles (
  id         vndbid NOT NULL,
  lang       language NOT NULL,
  title      text NOT NULL,
  latin      text,
  official   boolean NOT NULL,
  PRIMARY KEY(id, lang)
);

CREATE TABLE vn_titles_hist (
  chid       integer NOT NULL,
  lang       language NOT NULL,
  title      text NOT NULL,
  latin      text,
  official   boolean NOT NULL,
  PRIMARY KEY(chid, lang)
);

INSERT INTO vn_titles      SELECT id,   olang, CASE WHEN original = '' THEN title ELSE original END, CASE WHEN original = '' THEN NULL ELSE title END, true FROM vn;
INSERT INTO vn_titles_hist SELECT chid, olang, CASE WHEN original = '' THEN title ELSE original END, CASE WHEN original = '' THEN NULL ELSE title END, true FROM vn_hist;

ALTER TABLE vn_titles                ADD CONSTRAINT vn_titles_id_fkey                  FOREIGN KEY (id)        REFERENCES vn            (id);
ALTER TABLE vn_titles_hist           ADD CONSTRAINT vn_titles_hist_chid_fkey           FOREIGN KEY (chid)      REFERENCES changes       (id) ON DELETE CASCADE;
ALTER TABLE vn                       ADD CONSTRAINT vn_olang_fkey                      FOREIGN KEY (id,olang)  REFERENCES vn_titles     (id,lang)   DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_hist                  ADD CONSTRAINT vn_hist_olang_fkey                 FOREIGN KEY (chid,olang)REFERENCES vn_titles_hist(chid,lang) DEFERRABLE INITIALLY DEFERRED;

-- TODO: actually drop
ALTER TABLE vn RENAME COLUMN original TO old_original;
ALTER TABLE vn RENAME COLUMN title TO old_title;
--ALTER TABLE vn RENAME COLUMN old_original TO original;
--ALTER TABLE vn RENAME COLUMN old_title TO title;
--ALTER TABLE vn DROP COLUMN original, DROP COLUMN title;

CREATE VIEW vnt AS SELECT v.*, COALESCE(vo.latin, vo.title) AS title, CASE WHEN vo.latin IS NULL THEN '' ELSE vo.title END AS alttitle FROM vn v JOIN vn_titles vo ON vo.id = v.id AND vo.lang = v.olang;

ALTER TABLE users ADD COLUMN title_langs jsonb, ADD COLUMN alttitle_langs jsonb;

COMMIT;
\i sql/func.sql
\i sql/editfunc.sql
\i sql/perms.sql
