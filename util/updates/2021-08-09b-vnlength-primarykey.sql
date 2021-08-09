-- Recreate the vn_length_votes table to cleanly add a primary key and for more efficient storage.
-- The table layout had gotten messy with all the recent edits.
BEGIN;
DROP INDEX vn_length_votes_pkey;
DROP INDEX vn_length_votes_uid;
ALTER TABLE vn_length_votes RENAME TO vn_length_votes_tmp;

CREATE TABLE vn_length_votes (
  id         SERIAL PRIMARY KEY,
  vid        vndbid NOT NULL, -- [pub]
  date       timestamptz NOT NULL DEFAULT NOW(), -- [pub]
  length     smallint NOT NULL, -- [pub] minutes
  speed      smallint NOT NULL, -- [pub] 0=slow, 1=normal, 2=fast
  uid        vndbid, -- [pub]
  ignore     boolean NOT NULL DEFAULT false, -- [pub]
  rid        vndbid[] NOT NULL, -- [pub]
  notes      text NOT NULL DEFAULT '' -- [pub]
);

INSERT INTO vn_length_votes (vid,date,uid,length,speed,ignore,rid,notes)
    SELECT vid,date,uid,length,speed,ignore,rid,notes FROM vn_length_votes_tmp;

CREATE UNIQUE INDEX vn_length_votes_vid_uid ON vn_length_votes (vid, uid);
CREATE        INDEX vn_length_votes_uid    ON vn_length_votes (uid);
ALTER TABLE vn_length_votes          ADD CONSTRAINT vn_length_votes_vid_fkey           FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE vn_length_votes          ADD CONSTRAINT vn_length_votes_uid_fkey           FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE SET DEFAULT;
COMMIT;
\i sql/perms.sql
