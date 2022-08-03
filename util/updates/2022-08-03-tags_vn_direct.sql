CREATE TABLE tags_vn_direct (
  tag     vndbid NOT NULL,
  vid     vndbid NOT NULL,
  rating  real NOT NULL,
  spoiler smallint NOT NULL,
  lie     boolean NOT NULL
);
\i sql/func.sql
\i sql/perms.sql
SELECT tag_vn_calc(NULL);
