CREATE TABLE changes_patrolled (
  id         integer NOT NULL,
  uid        vndbid NOT NULL,
  PRIMARY KEY(id,uid)
);
ALTER TABLE changes_patrolled        ADD CONSTRAINT changes_patrolled_id_fkey          FOREIGN KEY (id)        REFERENCES changes       (id) ON DELETE CASCADE;
ALTER TABLE changes_patrolled        ADD CONSTRAINT changes_patrolled_uid_fkey         FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;
\i sql/perms.sql
