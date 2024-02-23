BEGIN;

CREATE TABLE quotes_tmp (
  id        serial PRIMARY KEY,
  vid       vndbid NOT NULL,
  cid       vndbid,
  addedby   vndbid,
  rand      real,
  score     smallint NOT NULL DEFAULT 0,
  state     smallint NOT NULL DEFAULT 0,
  quote     text NOT NULL
);

CREATE TABLE quotes_log (
  date      timestamptz NOT NULL DEFAULT NOW(),
  id        integer NOT NULL,
  uid       vndbid,
  action    text NOT NULL
);

CREATE TABLE quotes_votes (
  date      timestamptz NOT NULL DEFAULT NOW(),
  id        integer NOT NULL,
  uid       vndbid NOT NULL,
  vote      smallint NOT NULL,
  PRIMARY KEY(id, uid)
);

WITH s (date, uid, vid, quote) AS (
  SELECT DISTINCT ON (detail) date, by_uid, regexp_replace(detail, '^([^ ]+): .+$', '\1', '')::vndbid, regexp_replace(detail, '^[^ ]+: (.+)$', '\1', '')
    FROM audit_log a
   WHERE action = 'submit quote'
     AND EXISTS(SELECT 1 FROM users WHERE id = by_uid)
   ORDER BY detail, date
), q AS (
  INSERT INTO quotes_tmp (vid, rand, addedby, state, quote, score)
SELECT q.vid, q.rand, s.uid, CASE WHEN q.approved THEN 1 ELSE 0 END, q.quote, 1
    FROM quotes q
    LEFT JOIN s ON s.vid = q.vid AND s.quote = q.quote
   ORDER BY s.date NULLS FIRST
  RETURNING id, vid, quote
), l AS (
  INSERT INTO quotes_log
  SELECT COALESCE(s.date, '2023-09-15 12:00 UTC'), q.id, s.uid, CASE WHEN s.uid IS NULL THEN 'Added to the database before the submission form existed' ELSE 'Submitted' END
    FROM q LEFT JOIN s ON s.vid = q.vid AND s.quote = q.quote
  RETURNING date, id, uid
) INSERT INTO quotes_votes
  SELECT date, id, COALESCE(uid, 'u1'), 1 FROM l;


DROP TABLE quotes;
ALTER TABLE quotes_tmp RENAME TO quotes;
ALTER INDEX quotes_tmp_pkey RENAME TO quotes_pkey;
ALTER SEQUENCE quotes_tmp_id_seq RENAME TO quotes_id_seq;


CREATE        INDEX quotes_rand            ON quotes (rand) WHERE rand IS NOT NULL;
CREATE        INDEX quotes_vid             ON quotes (vid);
CREATE        INDEX quotes_log_id          ON quotes_log (id);
ALTER TABLE quotes                   ADD CONSTRAINT quotes_vid_fkey                    FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE quotes                   ADD CONSTRAINT quotes_cid_fkey                    FOREIGN KEY (cid)       REFERENCES chars         (id);
ALTER TABLE quotes                   ADD CONSTRAINT quotes_addedby_fkey                FOREIGN KEY (addedby)   REFERENCES users         (id) ON DELETE SET DEFAULT;
ALTER TABLE quotes_log               ADD CONSTRAINT quotes_log_id_fkey                 FOREIGN KEY (id)        REFERENCES quotes        (id) ON DELETE CASCADE;
ALTER TABLE quotes_log               ADD CONSTRAINT quotes_log_uid_fkey                FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE SET DEFAULT;
ALTER TABLE quotes_votes             ADD CONSTRAINT quotes_votes_id_fkey               FOREIGN KEY (id)        REFERENCES quotes        (id) ON DELETE CASCADE;
ALTER TABLE quotes_votes             ADD CONSTRAINT quotes_votes_uid_fkey              FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;


GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vndb_site;
GRANT SELECT, INSERT, UPDATE         ON quotes                   TO vndb_site;
GRANT SELECT, INSERT                 ON quotes_log               TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON quotes_votes             TO vndb_site;
GRANT SELECT,         UPDATE         ON quotes                   TO vndb_multi;


CREATE OR REPLACE FUNCTION update_quotes_votes_cache() RETURNS trigger AS $$
BEGIN
  UPDATE quotes
     SET score = (SELECT SUM(vote) FROM quotes_votes WHERE quotes_votes.id = quotes.id)
   WHERE id IN(OLD.id, NEW.id);
  RETURN NULL;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER quotes_votes_cache AFTER INSERT OR UPDATE OR DELETE ON quotes_votes FOR EACH ROW EXECUTE PROCEDURE update_quotes_votes_cache();

COMMIT;

\i sql/func.sql
