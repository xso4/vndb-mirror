BEGIN;

ALTER TABLE chars_traits      DROP CONSTRAINT chars_traits_tid_fkey;
ALTER TABLE chars_traits_hist DROP CONSTRAINT chars_traits_hist_tid_fkey;
ALTER TABLE traits            DROP CONSTRAINT traits_group_fkey;
ALTER TABLE traits_parents    DROP CONSTRAINT traits_parents_trait_fkey;
ALTER TABLE traits_parents    DROP CONSTRAINT traits_parents_parent_fkey;

DROP TRIGGER insert_notify ON traits;
DROP TRIGGER stats_cache_new  ON traits;
DROP TRIGGER stats_cache_edit ON traits;

ALTER TABLE traits ADD COLUMN hidden boolean NOT NULL DEFAULT FALSE;
ALTER TABLE traits ADD COLUMN locked boolean NOT NULL DEFAULT TRUE;
UPDATE traits SET hidden = (state <> 2), locked = (state = 1);
ALTER TABLE traits DROP COLUMN state;

ALTER TABLE traits ALTER COLUMN id DROP DEFAULT;
ALTER TABLE traits ALTER COLUMN id TYPE vndbid USING vndbid('i', id);
ALTER TABLE traits ALTER COLUMN id SET DEFAULT vndbid('i', nextval('traits_id_seq')::int);
ALTER TABLE traits ADD CONSTRAINT traits_id_check CHECK(vndbid_type(id) = 'i');

ALTER TABLE traits ALTER COLUMN "group" TYPE vndbid USING vndbid('i', "group");
ALTER TABLE traits ALTER COLUMN name SET DEFAULT '';

ALTER TABLE traits_parents    RENAME COLUMN trait TO id;
ALTER TABLE traits_parents    ALTER COLUMN id     TYPE vndbid USING vndbid('i', id);
ALTER TABLE traits_parents    ALTER COLUMN parent TYPE vndbid USING vndbid('i', parent);

ALTER TABLE traits_chars      ALTER COLUMN tid TYPE vndbid USING vndbid('i', tid);
ALTER TABLE chars_traits      ALTER COLUMN tid TYPE vndbid USING vndbid('i', tid);
ALTER TABLE chars_traits_hist ALTER COLUMN tid TYPE vndbid USING vndbid('i', tid);

CREATE TABLE traits_hist (
  chid          integer NOT NULL,
  "order"       smallint NOT NULL DEFAULT 0,
  defaultspoil  smallint NOT NULL DEFAULT 0,
  sexual        boolean NOT NULL DEFAULT false,
  searchable    boolean NOT NULL DEFAULT true,
  applicable    boolean NOT NULL DEFAULT true,
  name          varchar(250) NOT NULL DEFAULT '',
  alias         varchar(500) NOT NULL DEFAULT '',
  description   text NOT NULL DEFAULT ''
);

CREATE TABLE traits_parents_hist (
  chid     integer NOT NULL,
  parent   vndbid NOT NULL,
  PRIMARY KEY(chid, parent)
);


INSERT INTO changes (requester,itemid,rev,ihid,ilock,comments)
    SELECT 'u1', id, 1, hidden, locked,
'Automated import from when the trait database did not keep track of change histories.
This trait was initially submitted by '||coalesce(nullif(addedby::text, 'u1'), 'an anonymous user')||' on '||added::date||', but has no doubt been updated over time by moderators.'
      FROM traits;

INSERT INTO traits_hist (chid, "order", defaultspoil, sexual, searchable, applicable, name, description, alias)
    SELECT c.id, t."order", t.defaultspoil, t.sexual, t.searchable, t.applicable, t.name, t.description, t.alias
      FROM traits t JOIN changes c ON c.itemid = t.id;

INSERT INTO traits_parents_hist (chid, parent) SELECT c.id, t.parent FROM traits_parents t JOIN changes c ON c.itemid = t.id;

ALTER TABLE traits DROP COLUMN addedby;

\i sql/func.sql
\i sql/editfunc.sql

COMMIT;

\i sql/tableattrs.sql
\i sql/triggers.sql
\i sql/perms.sql
