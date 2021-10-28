CREATE TABLE users_username_hist (
  id    vndbid NOT NULL,
  date  timestamptz NOT NULL DEFAULT NOW(),
  old   text NOT NULL,
  new   text NOT NULL,
  PRIMARY KEY(id, date)
);
ALTER TABLE users_username_hist      ADD CONSTRAINT users_username_hist_id_fkey        FOREIGN KEY (id)        REFERENCES users         (id) ON DELETE CASCADE;
\i sql/perms.sql

INSERT INTO users_username_hist (id, date, old, new)
     SELECT affected_uid, date
          , regexp_replace(detail, 'username: "([^"]+)" -> "([^"]+)"', '\1', '') AS old
          , regexp_replace(detail, 'username: "([^"]+)" -> "([^"]+)"', '\2', '') AS new
       FROM audit_log
      WHERE detail ~ 'username: "([^"]+)" -> "([^"]+)"' AND EXISTS(SELECT 1 FROM users WHERE id = affected_uid);
