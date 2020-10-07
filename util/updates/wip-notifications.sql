-- Simplified triggers, all the logic is consolidated in notify().
DROP TRIGGER notify_pm ON threads_posts;
DROP TRIGGER notify_announce ON threads_posts;
DROP FUNCTION notify_pm();
DROP FUNCTION notify_announce();

DROP FUNCTION notify_dbdel(dbentry_type, edit_rettype);
DROP FUNCTION notify_dbedit(dbentry_type, edit_rettype);
DROP FUNCTION notify_listdel(dbentry_type, edit_rettype);

-- Table changes
ALTER TABLE notifications ALTER COLUMN ntype TYPE notification_ntype[] USING ARRAY[ntype];
ALTER TABLE notifications DROP COLUMN c_title;
ALTER TABLE notifications DROP COLUMN c_byuser;

-- Subscriptions
ALTER TYPE notification_ntype ADD VALUE 'subpost' AFTER 'comment';
ALTER TYPE notification_ntype ADD VALUE 'subedit' AFTER 'subpost';
ALTER TYPE notification_ntype ADD VALUE 'subreview' AFTER 'subedit';

CREATE TABLE notification_subs (
  uid         integer NOT NULL,
  iid         vndbid NOT NULL,
  subnum      boolean,
  subreview   boolean NOT NULL DEFAULT false,
  PRIMARY KEY(iid,uid)
);
ALTER TABLE notification_subs        ADD CONSTRAINT notification_subs_uid_fkey         FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;

\i sql/func.sql
\i sql/triggers.sql
\i sql/perms.sql
