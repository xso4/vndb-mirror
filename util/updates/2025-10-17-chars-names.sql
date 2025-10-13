\i sql/schema.sql

DROP VIEW IF EXISTS charst, moe.chars, moe.charst CASCADE;

INSERT INTO chars_names SELECT id, c_lang, name, latin FROM chars;
INSERT INTO chars_names_hist SELECT ch.chid, c.c_lang, ch.name, ch.latin FROM chars_hist ch JOIN changes h ON h.id = ch.chid JOIN chars c ON c.id = h.itemid;

INSERT INTO chars_alias SELECT id, 0, a, null FROM chars, regexp_split_to_table(alias, E'\n') a(a) WHERE a <> '';
INSERT INTO chars_alias_hist SELECT DISTINCT chid, 0, a, null FROM chars_hist, regexp_split_to_table(alias, E'\n') a(a) WHERE a <> '';

ALTER TABLE chars      DROP COLUMN name, DROP COLUMN latin, DROP COLUMN alias;
ALTER TABLE chars_hist DROP COLUMN name, DROP COLUMN latin, DROP COLUMN alias;

\i sql/schema.sql
\i sql/tableattrs.sql

\i sql/func.sql
\i sql/editfunc.sql
\i sql/perms.sql
