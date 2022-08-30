CREATE TABLE users_prefs_tags (
  id     vndbid NOT NULL,
  tid    vndbid NOT NULL,
  spoil  smallint NOT NULL,
  childs boolean NOT NULL,
  PRIMARY KEY(id, tid)
);

ALTER TABLE users_prefs_tags         ADD CONSTRAINT users_prefs_tags_id_fkey           FOREIGN KEY (id)        REFERENCES users         (id) ON DELETE CASCADE;
ALTER TABLE users_prefs_tags         ADD CONSTRAINT users_prefs_tags_tid_fkey          FOREIGN KEY (tid)       REFERENCES tags          (id) ON DELETE CASCADE;

CREATE TABLE users_prefs_traits (
  id     vndbid NOT NULL,
  tid    vndbid NOT NULL,
  spoil  smallint NOT NULL,
  childs boolean NOT NULL,
  PRIMARY KEY(id, tid)
);

ALTER TABLE users_prefs_traits       ADD CONSTRAINT users_prefs_traits_id_fkey         FOREIGN KEY (id)        REFERENCES users         (id) ON DELETE CASCADE;
ALTER TABLE users_prefs_traits       ADD CONSTRAINT users_prefs_traits_tid_fkey        FOREIGN KEY (tid)       REFERENCES traits        (id) ON DELETE CASCADE;

\i sql/perms.sql
