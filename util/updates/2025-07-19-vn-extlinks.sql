ALTER TYPE extlink_site ADD VALUE 'renai' after 'playstation_na';
ALTER TYPE extlink_site ADD VALUE 'encubed' after 'egs_creator';

BEGIN;

CREATE TABLE vn_extlinks (
  id      vndbid(v) NOT NULL,
  c_site  extlink_site NOT NULL,
  link    integer NOT NULL,
  PRIMARY KEY(id, link)
);

CREATE TABLE vn_extlinks_hist (
  chid    integer NOT NULL,
  link    integer NOT NULL,
  PRIMARY KEY(chid, link)
);

INSERT INTO extlinks (site, value)
        SELECT 'wikidata'::extlink_site, l_wikidata::text FROM vn WHERE l_wikidata IS NOT NULL
  UNION SELECT 'wp',       l_wp             FROM vn      WHERE l_wp <> ''
  UNION SELECT 'encubed',  l_encubed        FROM vn      WHERE l_encubed <> ''
  UNION SELECT 'renai',    l_renai          FROM vn      WHERE l_renai <> ''
  UNION SELECT 'wikidata', l_wikidata::text FROM vn_hist WHERE l_wikidata IS NOT NULL
  UNION SELECT 'wp',       l_wp             FROM vn_hist WHERE l_wp <> ''
  UNION SELECT 'encubed',  l_encubed        FROM vn_hist WHERE l_encubed <> ''
  UNION SELECT 'renai',    l_renai          FROM vn_hist WHERE l_renai <> ''
  EXCEPT SELECT site, value FROM extlinks;

INSERT INTO vn_extlinks (id, c_site, link)
            SELECT v.id, l.site, l.id FROM vn v JOIN extlinks l ON l.site = 'wikidata' AND l.value = v.l_wikidata::text WHERE v.l_wikidata IS NOT NULL
  UNION ALL SELECT v.id, l.site, l.id FROM vn v JOIN extlinks l ON l.site = 'wp' AND l.value = v.l_wp WHERE v.l_wp <> ''
  UNION ALL SELECT v.id, l.site, l.id FROM vn v JOIN extlinks l ON l.site = 'encubed' AND l.value = v.l_encubed WHERE v.l_encubed <> ''
  UNION ALL SELECT v.id, l.site, l.id FROM vn v JOIN extlinks l ON l.site = 'renai' AND l.value = v.l_renai WHERE v.l_renai <> '';

INSERT INTO vn_extlinks_hist (chid, link)
            SELECT v.chid, l.id FROM vn_hist v JOIN extlinks l ON l.site = 'wikidata' AND l.value = v.l_wikidata::text WHERE v.l_wikidata IS NOT NULL
  UNION ALL SELECT v.chid, l.id FROM vn_hist v JOIN extlinks l ON l.site = 'wp' AND l.value = v.l_wp WHERE v.l_wp <> ''
  UNION ALL SELECT v.chid, l.id FROM vn_hist v JOIN extlinks l ON l.site = 'encubed' AND l.value = v.l_encubed WHERE v.l_encubed <> ''
  UNION ALL SELECT v.chid, l.id FROM vn_hist v JOIN extlinks l ON l.site = 'renai' AND l.value = v.l_renai WHERE v.l_renai <> '';

DROP VIEW vnt, moe.vn, moe.vnt CASCADE;
DROP TRIGGER vn_wikidata_new       ON vn;
DROP TRIGGER vn_wikidata_edit      ON vn;
DROP TRIGGER vn_hist_wikidata_new  ON vn_hist;
DROP TRIGGER vn_hist_wikidata_edit ON vn_hist;
ALTER TABLE vn      DROP COLUMN l_wikidata, DROP COLUMN l_wp, DROP COLUMN l_encubed, DROP COLUMN l_renai;
ALTER TABLE vn_hist DROP COLUMN l_wikidata, DROP COLUMN l_wp, DROP COLUMN l_encubed, DROP COLUMN l_renai;

COMMIT;

\i sql/schema.sql
\i sql/func.sql
\i sql/editfunc.sql
\i sql/tableattrs.sql
\i sql/perms.sql

SELECT update_extlinks_cache(NULL);
