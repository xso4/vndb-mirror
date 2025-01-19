CREATE TABLE posts_patrolled (
  id       vndbid NOT NULL, -- threads.id or reviews.id
  num      integer NOT NULL,
  uid      vndbid(u) NOT NULL,
  PRIMARY KEY(id,num,uid)
);

ALTER TABLE posts_patrolled          ADD CONSTRAINT posts_patrolled_uid_fkey           FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;

GRANT SELECT, INSERT,         DELETE ON posts_patrolled          TO vndb_site;
