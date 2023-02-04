ALTER TABLE producers      ALTER COLUMN original DROP NOT NULL;
ALTER TABLE producers      ALTER COLUMN original DROP DEFAULT;
ALTER TABLE producers_hist ALTER COLUMN original DROP NOT NULL;
ALTER TABLE producers_hist ALTER COLUMN original DROP DEFAULT;
UPDATE producers      SET original = NULL WHERE original = '';
UPDATE producers_hist SET original = NULL WHERE original = '';

CREATE VIEW producerst AS
    SELECT id, type, lang, l_wikidata, locked, hidden, alias, website, "desc", l_wp, c_search
         , name, original AS altname, name AS sortname
      FROM producers;

\i sql/editfunc.sql
\i sql/func.sql
\i sql/perms.sql
