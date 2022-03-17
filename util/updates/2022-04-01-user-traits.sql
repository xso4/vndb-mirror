CREATE TABLE users_traits (
  id  vndbid NOT NULL,
  tid vndbid NOT NULL,
  PRIMARY KEY(id, tid)
);
ALTER TABLE users_traits             ADD CONSTRAINT users_traits_id_fkey               FOREIGN KEY (id)        REFERENCES users         (id) ON DELETE CASCADE;
ALTER TABLE users_traits             ADD CONSTRAINT users_traits_tid_fkey              FOREIGN KEY (tid)       REFERENCES traits        (id);
GRANT SELECT, INSERT, UPDATE, DELETE ON users_traits             TO vndb_site;
