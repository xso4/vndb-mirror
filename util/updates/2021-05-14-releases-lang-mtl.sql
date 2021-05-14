ALTER TABLE releases_lang      ADD COLUMN mtl boolean NOT NULL DEFAULT FALSE;
ALTER TABLE releases_lang_hist ADD COLUMN mtl boolean NOT NULL DEFAULT FALSE;
\i sql/editfunc.sql
\i sql/func.sql
