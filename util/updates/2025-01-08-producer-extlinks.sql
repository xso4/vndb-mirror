
BEGIN;

CREATE TABLE producers_extlinks (
  id      vndbid(p) NOT NULL,
  c_site  extlink_site NOT NULL,
  link    integer NOT NULL,
  PRIMARY KEY(id, link)
);

CREATE TABLE producers_extlinks_hist (
  chid    integer NOT NULL,
  link    integer NOT NULL,
  PRIMARY KEY(chid, link)
);

INSERT INTO extlinks (site, value)
        SELECT 'wikidata'::extlink_site, l_wikidata::text FROM producers WHERE l_wikidata <> 0
  UNION SELECT 'wp',       l_wp             FROM producers      WHERE l_wp <> ''
  UNION SELECT 'website',  website          FROM producers      WHERE website <> ''
  UNION SELECT 'wikidata', l_wikidata::text FROM producers_hist WHERE l_wikidata <> 0
  UNION SELECT 'wp',       l_wp             FROM producers_hist WHERE l_wp <> ''
  UNION SELECT 'website',  website          FROM producers_hist WHERE website <> ''
  EXCEPT SELECT site, value FROM extlinks;

INSERT INTO producers_extlinks (id, c_site, link)
            SELECT p.id, l.site, l.id FROM producers p JOIN extlinks l ON l.site = 'wikidata' AND l.value = p.l_wikidata::text WHERE p.l_wikidata <> 0
  UNION ALL SELECT p.id, l.site, l.id FROM producers p JOIN extlinks l ON l.site = 'wp' AND l.value = p.l_wp WHERE p.l_wp <> ''
  UNION ALL SELECT p.id, l.site, l.id FROM producers p JOIN extlinks l ON l.site = 'website' AND l.value = p.website WHERE p.website <> '';

INSERT INTO producers_extlinks_hist (chid, link)
            SELECT p.chid, l.id FROM producers_hist p JOIN extlinks l ON l.site = 'wikidata' AND l.value = p.l_wikidata::text WHERE p.l_wikidata <> 0
  UNION ALL SELECT p.chid, l.id FROM producers_hist p JOIN extlinks l ON l.site = 'wp' AND l.value = p.l_wp WHERE p.l_wp <> ''
  UNION ALL SELECT p.chid, l.id FROM producers_hist p JOIN extlinks l ON l.site = 'website' AND l.value = p.website WHERE p.website <> '';

SELECT update_extlinks_cache(NULL);

DROP VIEW producerst CASCADE;
DROP TRIGGER producers_wikidata_new       ON producers;
DROP TRIGGER producers_wikidata_edit      ON producers;
DROP TRIGGER producers_hist_wikidata_new  ON producers_hist;
DROP TRIGGER producers_hist_wikidata_edit ON producers_hist;
ALTER TABLE producers      DROP COLUMN l_wikidata, DROP COLUMN l_wp, DROP COLUMN website;
ALTER TABLE producers_hist DROP COLUMN l_wikidata, DROP COLUMN l_wp, DROP COLUMN website;

ALTER TYPE extlink_site ADD VALUE 'gamefaqs_comp' AFTER 'freem';
ALTER TYPE extlink_site ADD VALUE 'itch_dev' AFTER 'itch';
ALTER TYPE extlink_site ADD VALUE 'mobygames_comp' AFTER 'mobygames';

COMMIT;

\i sql/schema.sql
\i sql/func.sql
\i sql/editfunc.sql
\i sql/tableattrs.sql
\i sql/perms.sql
