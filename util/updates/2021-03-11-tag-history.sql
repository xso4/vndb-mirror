BEGIN;

-- 'deleted' state is now represented as (hidden && locked)
-- (hidden && !locked) now means 'awaiting moderation'
UPDATE vn        SET locked = true WHERE hidden AND NOT locked;
UPDATE producers SET locked = true WHERE hidden AND NOT locked;
UPDATE staff     SET locked = true WHERE hidden AND NOT locked;
UPDATE chars     SET locked = true WHERE hidden AND NOT locked;
UPDATE releases  SET locked = true WHERE hidden AND NOT locked;
UPDATE docs      SET locked = true WHERE hidden AND NOT locked;
UPDATE changes   SET ilock  = true WHERE ihid   AND NOT ilock;

ALTER TABLE tags_aliases DROP CONSTRAINT tags_aliases_tag_fkey;
ALTER TABLE tags_parents DROP CONSTRAINT tags_parents_tag_fkey;
ALTER TABLE tags_parents DROP CONSTRAINT tags_parents_parent_fkey;
ALTER TABLE tags_vn      DROP CONSTRAINT tags_vn_tag_fkey;

DROP TRIGGER insert_notify ON tags;
DROP TRIGGER stats_cache_new  ON tags;
DROP TRIGGER stats_cache_edit ON tags;

-- Move tags_alias into tags as 'alias' column, to be consistent with how aliases are stored for traits.
-- No real need to enforce uniqueness on aliasses as they're just search helpers.
ALTER TABLE tags ADD COLUMN alias varchar(500) NOT NULL DEFAULT '';
UPDATE tags SET alias = COALESCE((SELECT string_agg(alias, E'\n') FROM tags_aliases WHERE tag = tags.id), '');
DROP TABLE tags_aliases;

ALTER TABLE tags ALTER COLUMN name SET DEFAULT '';

-- State -> hidden,locked
ALTER TABLE tags ADD COLUMN hidden boolean NOT NULL DEFAULT FALSE;
ALTER TABLE tags ADD COLUMN locked boolean NOT NULL DEFAULT TRUE;
UPDATE tags SET hidden = (state <> 2), locked = (state = 1);
ALTER TABLE tags DROP COLUMN state;

-- id -> vndbid
ALTER TABLE tags ALTER COLUMN id DROP DEFAULT;
ALTER TABLE tags ALTER COLUMN id TYPE vndbid USING vndbid('g', id);
ALTER TABLE tags ALTER COLUMN id SET DEFAULT vndbid('g', nextval('tags_id_seq')::int);
ALTER TABLE tags ADD CONSTRAINT tags_id_check CHECK(vndbid_type(id) = 'g');

ALTER TABLE tags_parents RENAME COLUMN tag TO id;
ALTER TABLE tags_parents ALTER COLUMN id     TYPE vndbid USING vndbid('g', id);
ALTER TABLE tags_parents ALTER COLUMN parent TYPE vndbid USING vndbid('g', parent);


CREATE TABLE tags_hist (
  chid         integer NOT NULL PRIMARY KEY,
  cat          tag_category NOT NULL DEFAULT 'cont',
  defaultspoil smallint NOT NULL DEFAULT 0,
  searchable   boolean NOT NULL DEFAULT TRUE,
  applicable   boolean NOT NULL DEFAULT TRUE,
  name         varchar(250) NOT NULL DEFAULT '',
  description  text NOT NULL DEFAULT '',
  alias        varchar(500) NOT NULL DEFAULT ''
);

CREATE TABLE tags_parents_hist (
  chid     integer NOT NULL,
  parent   vndbid NOT NULL,
  PRIMARY KEY(chid, parent)
);

ALTER TABLE tags_vn         ALTER COLUMN tag TYPE vndbid USING vndbid('g', tag);
ALTER TABLE tags_vn_inherit ALTER COLUMN tag TYPE vndbid USING vndbid('g', tag);

INSERT INTO changes (requester,itemid,rev,ihid,ilock,comments)
    SELECT 'u1', id, 1, hidden, locked,
'Automated import from when the tag database did not keep track of change histories.
This tag was initially submitted by '||coalesce(nullif(addedby::text, 'u1'), 'an anonymous user')||' on '||added::date||', but has no doubt been updated over time by moderators.'
      FROM tags;

INSERT INTO tags_hist (chid, cat, defaultspoil, searchable, applicable, name, description, alias)
    SELECT c.id, t.cat, t.defaultspoil, t.searchable, t.applicable, t.name, t.description, t.alias
      FROM tags t JOIN changes c ON c.itemid = t.id;

INSERT INTO tags_parents_hist (chid, parent) SELECT c.id, t.parent FROM tags_parents t JOIN changes c ON c.itemid = t.id;

ALTER TABLE tags DROP COLUMN addedby;


\i sql/func.sql
\i sql/editfunc.sql

COMMIT;

\i sql/tableattrs.sql
\i sql/triggers.sql
\i sql/perms.sql
