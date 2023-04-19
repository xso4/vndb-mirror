CREATE TABLE shop_jastusa (
  lastfetch  timestamptz,
  deadsince  timestamptz,
  id         text NOT NULL PRIMARY KEY,
  price      text NOT NULL DEFAULT '',
  slug       text NOT NULL DEFAULT ''
);
\i sql/perms.sql
