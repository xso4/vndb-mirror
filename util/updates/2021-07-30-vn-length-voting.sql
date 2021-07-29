CREATE TABLE vn_length_votes (
  vid        vndbid NOT NULL,
  rid        vndbid NOT NULL,
  date       timestamptz NOT NULL DEFAULT NOW(),
  uid        vndbid,
  length     smallint NOT NULL, -- minutes
  notes      text NOT NULL DEFAULT ''
);
ALTER TABLE vn_length_votes          ADD CONSTRAINT vn_length_votes_vid_fkey           FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE vn_length_votes          ADD CONSTRAINT vn_length_votes_rid_fkey           FOREIGN KEY (rid)       REFERENCES releases      (id);
ALTER TABLE vn_length_votes          ADD CONSTRAINT vn_length_votes_uid_fkey           FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE SET DEFAULT;
CREATE UNIQUE INDEX vn_length_votes_pkey   ON vn_length_votes (vid, uid);

-- DEFAULT false while it's in development.
ALTER TABLE users ADD COLUMN perm_lengthvote boolean NOT NULL DEFAULT false;

\i sql/perms.sql
