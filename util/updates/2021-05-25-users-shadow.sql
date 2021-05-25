CREATE TABLE users_shadow (
  id             vndbid NOT NULL PRIMARY KEY,
  perm_usermod   boolean NOT NULL DEFAULT false,
  mail           varchar(100) NOT NULL,
  passwd         bytea NOT NULL DEFAULT ''
);

BEGIN;
INSERT INTO users_shadow SELECT id, perm_usermod, mail, passwd FROM users;

ALTER TABLE users_shadow             ADD CONSTRAINT users_shadow_id_fkey               FOREIGN KEY (id)        REFERENCES users         (id) ON DELETE CASCADE;

ALTER TABLE users DROP COLUMN perm_usermod;
ALTER TABLE users DROP COLUMN mail;
ALTER TABLE users DROP COLUMN passwd;
COMMIT;

\i sql/perms.sql
\i sql/func.sql
