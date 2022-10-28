-- This migration script is written so that it can be run while keeping VNDB
-- online in read-only mode. Any writes to the database while this script is
-- active will likely result in a deadlock or a bit of data loss.

-- (An older version of this script attempted to do an in-place UPDATE on
-- ulist_vns, but postgres didn't properly optimize that query in production
-- and ended up taking the site down for 30 minutes. This version is both
-- faster and doesn't require the site to go fully down)

CREATE TABLE ulist_vns_tmp (
  uid         vndbid NOT NULL,
  vid         vndbid NOT NULL,
  added       timestamptz NOT NULL DEFAULT NOW(),
  lastmod     timestamptz NOT NULL DEFAULT NOW(),
  vote_date   timestamptz,
  started     date,
  finished    date,
  vote        smallint,
  c_private   boolean NOT NULL DEFAULT true,
  labels      smallint[] NOT NULL DEFAULT '{}',
  notes       text NOT NULL DEFAULT ''
);

INSERT INTO ulist_vns_tmp
  SELECT uv.uid, uv.vid, uv.added, uv.lastmod, uv.vote_date, uv.started, uv.finished, uv.vote, coalesce(l.private, true), coalesce(l.labels, '{}'), uv.notes
    FROM ulist_vns uv
    LEFT JOIN (
        SELECT uvl.uid, uvl.vid, bool_and(ul.private), array_agg(uvl.lbl::smallint ORDER BY uvl.lbl)
          FROM ulist_vns_labels uvl
          JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl
         GROUP BY uvl.uid, uvl.vid
    ) l(uid, vid, private, labels) ON l.uid = uv.uid AND l.vid = uv.vid
   ORDER BY uv.uid, uv.vid;

-- Attempt a perfect reconstruction of 'ulist_vns', so that constraint & index
-- names match those of a newly created table with the correct name.
ALTER INDEX ulist_vns_pkey RENAME TO ulist_vns_old_pkey;
ALTER INDEX ulist_vns_voted RENAME TO ulist_vns_old_voted;

\timing
ALTER TABLE ulist_vns_tmp ADD CONSTRAINT ulist_vns_pkey PRIMARY KEY (uid, vid);
ALTER TABLE ulist_vns_tmp ADD CONSTRAINT ulist_vns_vote_check CHECK(vote IS NULL OR vote BETWEEN 10 AND 100);
CREATE INDEX ulist_vns_voted        ON ulist_vns_tmp (vid, vote_date) WHERE vote IS NOT NULL;
ALTER TABLE ulist_vns_tmp                ADD CONSTRAINT ulist_vns_uid_fkey                 FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;
ALTER TABLE ulist_vns_tmp                ADD CONSTRAINT ulist_vns_vid_fkey                 FOREIGN KEY (vid)       REFERENCES vn            (id);

ANALYZE ulist_vns_tmp;
GRANT SELECT, INSERT, UPDATE, DELETE ON ulist_vns_tmp            TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON ulist_vns_tmp            TO vndb_multi;

BEGIN;
ALTER TABLE ulist_vns RENAME TO ulist_vns_old;
ALTER TABLE ulist_vns_tmp RENAME TO ulist_vns;
COMMIT;


-- Let's not \i SQL files here, since we're running this script on an older commit.

-- From util.sql

CREATE OR REPLACE FUNCTION array_set(arr anycompatiblearray, elem anycompatible) RETURNS anycompatiblearray AS $$
DECLARE
  ret arr%TYPE;
  e elem%TYPE;
  added boolean := false;
BEGIN
  FOREACH e IN ARRAY arr LOOP
    IF e = elem THEN RETURN arr;
    ELSIF added or e < elem THEN ret := ret || e;
    ELSE
      ret := ret || elem || e;
      added := true;
    END IF;
  END LOOP;
  RETURN CASE WHEN added THEN ret ELSE ret || elem END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;



-- From func.sql

CREATE OR REPLACE FUNCTION update_users_ulist_stats(vndbid) RETURNS void AS $$
BEGIN
  WITH cnt(uid, votes, vns, wish) AS (
    SELECT u.id
         , COUNT(uv.vid) FILTER (WHERE NOT uv.c_private AND uv.vote IS NOT NULL) -- Voted
         , COUNT(uv.vid) FILTER (WHERE NOT uv.c_private AND NOT (uv.labels <@ ARRAY[5,6]::smallint[])) -- Labelled, but not wishlish/blacklist
         , COUNT(uv.vid) FILTER (WHERE uwish.private IS NOT DISTINCT FROM false AND uv.labels && ARRAY[5::smallint]) -- Wishlist
      FROM users u
      LEFT JOIN ulist_vns uv ON uv.uid = u.id
      LEFT JOIN ulist_labels uwish ON uwish.uid = u.id AND uwish.id = 5
     WHERE $1 IS NULL OR u.id = $1
     GROUP BY u.id
  ) UPDATE users SET c_votes = votes, c_vns = vns, c_wish = wish
      FROM cnt WHERE id = uid AND (c_votes, c_vns, c_wish) IS DISTINCT FROM (votes, vns, wish);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_users_ulist_private(vndbid, vndbid) RETURNS void AS $$
BEGIN
  WITH p(uid,vid,private) AS (
    SELECT uv.uid, uv.vid, COALESCE(bool_and(l.private), true)
      FROM ulist_vns uv
      LEFT JOIN unnest(uv.labels) x(id) ON true
      LEFT JOIN ulist_labels l ON l.id = x.id AND l.uid = uv.uid
     WHERE ($1 IS NULL OR uv.uid = $1)
       AND ($2 IS NULL OR uv.vid = $2)
     GROUP BY uv.uid, uv.vid
  ) UPDATE ulist_vns SET c_private = p.private FROM p
     WHERE ulist_vns.uid = p.uid AND ulist_vns.vid = p.vid AND ulist_vns.c_private <> p.private;
END;
$$ LANGUAGE plpgsql;



-- From triggers.sql

CREATE OR REPLACE FUNCTION ulist_voted_label() RETURNS trigger AS $$
BEGIN
    NEW.labels := CASE WHEN NEW.vote IS NULL THEN array_remove(NEW.labels, 7) ELSE array_set(NEW.labels, 7) END;
    RETURN NEW;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER ulist_voted_label_ins BEFORE INSERT ON ulist_vns FOR EACH ROW EXECUTE PROCEDURE ulist_voted_label();
CREATE TRIGGER ulist_voted_label_upd BEFORE UPDATE ON ulist_vns FOR EACH ROW WHEN ((OLD.vote IS NULL) <> (NEW.vote IS NULL)) EXECUTE PROCEDURE ulist_voted_label();




ALTER TABLE ulist_labels ALTER COLUMN id TYPE smallint;


-- These should be run after restarting vndb.pl with the new codebase.
DROP TABLE ulist_vns_labels;
DROP TABLE ulist_vns_old;
