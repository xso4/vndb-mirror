\i sql/schema.sql
\i sql/tableattrs.sql

DROP TRIGGER staff_wikidata_new       ON staff;
DROP TRIGGER staff_wikidata_edit      ON staff;
DROP TRIGGER staff_hist_wikidata_new  ON staff_hist;
DROP TRIGGER staff_hist_wikidata_edit ON staff_hist;

-- CARE:
--   staff.egs -> egs_creator

CREATE TEMPORARY TABLE tmp_rlinks AS
              SELECT id, 'toranoana'::extlink_site AS site, l_toranoana::text AS value FROM releases WHERE l_toranoana <> 0
    UNION ALL SELECT id, 'appstore',       l_appstore::text       FROM releases WHERE l_appstore         <> 0
    UNION ALL SELECT id, 'nintendo_jp',    l_nintendo_jp::text    FROM releases WHERE l_nintendo_jp      <> 0
    UNION ALL SELECT id, 'nintendo_hk',    l_nintendo_hk::text    FROM releases WHERE l_nintendo_hk      <> 0
    UNION ALL SELECT id, 'steam',          l_steam::text          FROM releases WHERE l_steam            <> 0
    UNION ALL SELECT id, 'digiket',        l_digiket::text        FROM releases WHERE l_digiket          <> 0
    UNION ALL SELECT id, 'melon',          l_melon::text          FROM releases WHERE l_melon            <> 0
    UNION ALL SELECT id, 'mg',             l_mg::text             FROM releases WHERE l_mg               <> 0
    UNION ALL SELECT id, 'getchu',         l_getchu::text         FROM releases WHERE l_getchu           <> 0
    UNION ALL SELECT id, 'getchudl',       l_getchudl::text       FROM releases WHERE l_getchudl         <> 0
    UNION ALL SELECT id, 'egs',            l_egs::text            FROM releases WHERE l_egs              <> 0
    UNION ALL SELECT id, 'erotrail',       l_erotrail::text       FROM releases WHERE l_erotrail         <> 0
    UNION ALL SELECT id, 'melonjp',        l_melonjp::text        FROM releases WHERE l_melonjp          <> 0
    UNION ALL SELECT id, 'gamejolt',       l_gamejolt::text       FROM releases WHERE l_gamejolt         <> 0
    UNION ALL SELECT id, 'animateg',       l_animateg::text       FROM releases WHERE l_animateg         <> 0
    UNION ALL SELECT id, 'freem',          l_freem::text          FROM releases WHERE l_freem            <> 0
    UNION ALL SELECT id, 'novelgam',       l_novelgam::text       FROM releases WHERE l_novelgam         <> 0
    UNION ALL SELECT id, 'booth',          l_booth::text          FROM releases WHERE l_booth            <> 0
    UNION ALL SELECT id, 'patreonp',       l_patreonp::text       FROM releases WHERE l_patreonp         <> 0
    UNION ALL SELECT id, 'website',        website                FROM releases WHERE website            <> ''
    UNION ALL SELECT id, 'dlsite',         l_dlsite               FROM releases WHERE l_dlsite           <> ''
    UNION ALL SELECT id, 'dlsiteen',       l_dlsiteen             FROM releases WHERE l_dlsiteen         <> ''
    UNION ALL SELECT id, 'gog',            l_gog                  FROM releases WHERE l_gog              <> ''
    UNION ALL SELECT id, 'denpa',          l_denpa                FROM releases WHERE l_denpa            <> ''
    UNION ALL SELECT id, 'jlist',          l_jlist                FROM releases WHERE l_jlist            <> ''
    UNION ALL SELECT id, 'jastusa',        l_jastusa              FROM releases WHERE l_jastusa          <> ''
    UNION ALL SELECT id, 'itch',           l_itch                 FROM releases WHERE l_itch             <> ''
    UNION ALL SELECT id, 'nutaku',         l_nutaku               FROM releases WHERE l_nutaku           <> ''
    UNION ALL SELECT id, 'googplay',       l_googplay             FROM releases WHERE l_googplay         <> ''
    UNION ALL SELECT id, 'fakku',          l_fakku                FROM releases WHERE l_fakku            <> ''
    UNION ALL SELECT id, 'freegame',       l_freegame             FROM releases WHERE l_freegame         <> ''
    UNION ALL SELECT id, 'playstation_jp', l_playstation_jp       FROM releases WHERE l_playstation_jp   <> ''
    UNION ALL SELECT id, 'playstation_na', l_playstation_na       FROM releases WHERE l_playstation_na   <> ''
    UNION ALL SELECT id, 'playstation_eu', l_playstation_eu       FROM releases WHERE l_playstation_eu   <> ''
    UNION ALL SELECT id, 'playstation_hk', l_playstation_hk       FROM releases WHERE l_playstation_hk   <> ''
    UNION ALL SELECT id, 'nintendo',       l_nintendo             FROM releases WHERE l_nintendo         <> ''
    UNION ALL SELECT id, 'patreon',        l_patreon              FROM releases WHERE l_patreon          <> ''
    UNION ALL SELECT id, 'substar',        l_substar              FROM releases WHERE l_substar          <> ''
    UNION ALL SELECT id, 'gyutto',         x::text                FROM releases, unnest(l_gyutto) x(x) WHERE l_gyutto  <> '{}'
    UNION ALL SELECT id, 'dmm',            x                      FROM releases, unnest(l_dmm   ) x(x) WHERE l_dmm     <> '{}';

CREATE TEMPORARY TABLE tmp_rhlinks AS
              SELECT chid, 'toranoana'::extlink_site AS site, l_toranoana::text AS value FROM releases_hist WHERE l_toranoana <> 0
    UNION ALL SELECT chid, 'appstore',       l_appstore::text       FROM releases_hist WHERE l_appstore         <> 0
    UNION ALL SELECT chid, 'nintendo_jp',    l_nintendo_jp::text    FROM releases_hist WHERE l_nintendo_jp      <> 0
    UNION ALL SELECT chid, 'nintendo_hk',    l_nintendo_hk::text    FROM releases_hist WHERE l_nintendo_hk      <> 0
    UNION ALL SELECT chid, 'steam',          l_steam::text          FROM releases_hist WHERE l_steam            <> 0
    UNION ALL SELECT chid, 'digiket',        l_digiket::text        FROM releases_hist WHERE l_digiket          <> 0
    UNION ALL SELECT chid, 'melon',          l_melon::text          FROM releases_hist WHERE l_melon            <> 0
    UNION ALL SELECT chid, 'mg',             l_mg::text             FROM releases_hist WHERE l_mg               <> 0
    UNION ALL SELECT chid, 'getchu',         l_getchu::text         FROM releases_hist WHERE l_getchu           <> 0
    UNION ALL SELECT chid, 'getchudl',       l_getchudl::text       FROM releases_hist WHERE l_getchudl         <> 0
    UNION ALL SELECT chid, 'egs',            l_egs::text            FROM releases_hist WHERE l_egs              <> 0
    UNION ALL SELECT chid, 'erotrail',       l_erotrail::text       FROM releases_hist WHERE l_erotrail         <> 0
    UNION ALL SELECT chid, 'melonjp',        l_melonjp::text        FROM releases_hist WHERE l_melonjp          <> 0
    UNION ALL SELECT chid, 'gamejolt',       l_gamejolt::text       FROM releases_hist WHERE l_gamejolt         <> 0
    UNION ALL SELECT chid, 'animateg',       l_animateg::text       FROM releases_hist WHERE l_animateg         <> 0
    UNION ALL SELECT chid, 'freem',          l_freem::text          FROM releases_hist WHERE l_freem            <> 0
    UNION ALL SELECT chid, 'novelgam',       l_novelgam::text       FROM releases_hist WHERE l_novelgam         <> 0
    UNION ALL SELECT chid, 'booth',          l_booth::text          FROM releases_hist WHERE l_booth            <> 0
    UNION ALL SELECT chid, 'patreonp',       l_patreonp::text       FROM releases_hist WHERE l_patreonp         <> 0
    UNION ALL SELECT chid, 'website',        website                FROM releases_hist WHERE website            <> ''
    UNION ALL SELECT chid, 'dlsite',         l_dlsite               FROM releases_hist WHERE l_dlsite           <> ''
    UNION ALL SELECT chid, 'dlsiteen',       l_dlsiteen             FROM releases_hist WHERE l_dlsiteen         <> ''
    UNION ALL SELECT chid, 'gog',            l_gog                  FROM releases_hist WHERE l_gog              <> ''
    UNION ALL SELECT chid, 'denpa',          l_denpa                FROM releases_hist WHERE l_denpa            <> ''
    UNION ALL SELECT chid, 'jlist',          l_jlist                FROM releases_hist WHERE l_jlist            <> ''
    UNION ALL SELECT chid, 'jastusa',        l_jastusa              FROM releases_hist WHERE l_jastusa          <> ''
    UNION ALL SELECT chid, 'itch',           l_itch                 FROM releases_hist WHERE l_itch             <> ''
    UNION ALL SELECT chid, 'nutaku',         l_nutaku               FROM releases_hist WHERE l_nutaku           <> ''
    UNION ALL SELECT chid, 'googplay',       l_googplay             FROM releases_hist WHERE l_googplay         <> ''
    UNION ALL SELECT chid, 'fakku',          l_fakku                FROM releases_hist WHERE l_fakku            <> ''
    UNION ALL SELECT chid, 'freegame',       l_freegame             FROM releases_hist WHERE l_freegame         <> ''
    UNION ALL SELECT chid, 'playstation_jp', l_playstation_jp       FROM releases_hist WHERE l_playstation_jp   <> ''
    UNION ALL SELECT chid, 'playstation_na', l_playstation_na       FROM releases_hist WHERE l_playstation_na   <> ''
    UNION ALL SELECT chid, 'playstation_eu', l_playstation_eu       FROM releases_hist WHERE l_playstation_eu   <> ''
    UNION ALL SELECT chid, 'playstation_hk', l_playstation_hk       FROM releases_hist WHERE l_playstation_hk   <> ''
    UNION ALL SELECT chid, 'nintendo',       l_nintendo             FROM releases_hist WHERE l_nintendo         <> ''
    UNION ALL SELECT chid, 'patreon',        l_patreon              FROM releases_hist WHERE l_patreon          <> ''
    UNION ALL SELECT chid, 'substar',        l_substar              FROM releases_hist WHERE l_substar          <> ''
    UNION ALL SELECT chid, 'gyutto',         x::text                FROM releases_hist, unnest(l_gyutto) x(x) WHERE l_gyutto  <> '{}'
    UNION ALL SELECT chid, 'dmm',            x                      FROM releases_hist, unnest(l_dmm   ) x(x) WHERE l_dmm     <> '{}';

CREATE TEMPORARY TABLE tmp_slinks AS
              SELECT id, 'anidb'::extlink_site AS site, l_anidb::text AS value FROM staff WHERE l_anidb IS NOT NULL
    UNION ALL SELECT id, 'wikidata',    l_wikidata::text  FROM staff WHERE l_wikidata   IS NOT NULL
    UNION ALL SELECT id, 'egs_creator', l_egs::text       FROM staff WHERE l_egs        <> 0
    UNION ALL SELECT id, 'anison',      l_anison::text    FROM staff WHERE l_anison     <> 0
    UNION ALL SELECT id, 'pixiv',       l_pixiv::text     FROM staff WHERE l_pixiv      <> 0
    UNION ALL SELECT id, 'vgmdb',       l_vgmdb::text     FROM staff WHERE l_vgmdb      <> 0
    UNION ALL SELECT id, 'discogs',     l_discogs::text   FROM staff WHERE l_discogs    <> 0
    UNION ALL SELECT id, 'mobygames',   l_mobygames::text FROM staff WHERE l_mobygames  <> 0
    UNION ALL SELECT id, 'bgmtv',       l_bgmtv::text     FROM staff WHERE l_bgmtv      <> 0
    UNION ALL SELECT id, 'imdb',        l_imdb::text      FROM staff WHERE l_imdb       <> 0
    UNION ALL SELECT id, 'wp',          l_wp              FROM staff WHERE l_wp         <> ''
    UNION ALL SELECT id, 'website',     l_site            FROM staff WHERE l_site       <> ''
    UNION ALL SELECT id, 'twitter',     l_twitter         FROM staff WHERE l_twitter    <> ''
    UNION ALL SELECT id, 'scloud',      l_scloud          FROM staff WHERE l_scloud     <> ''
    UNION ALL SELECT id, 'patreon',     l_patreon         FROM staff WHERE l_patreon    <> ''
    UNION ALL SELECT id, 'substar',     l_substar         FROM staff WHERE l_substar    <> ''
    UNION ALL SELECT id, 'youtube',     l_youtube         FROM staff WHERE l_youtube    <> ''
    UNION ALL SELECT id, 'instagram',   l_instagram       FROM staff WHERE l_instagram  <> ''
    UNION ALL SELECT id, 'deviantar',   l_deviantar       FROM staff WHERE l_deviantar  <> ''
    UNION ALL SELECT id, 'tumblr',      l_tumblr          FROM staff WHERE l_tumblr     <> ''
    UNION ALL SELECT id, 'vndb',        l_vndb::text      FROM staff WHERE l_vndb       IS NOT NULL
    UNION ALL SELECT id, 'mbrainz',     l_mbrainz::text   FROM staff WHERE l_mbrainz    IS NOT NULL;

CREATE TEMPORARY TABLE tmp_shlinks AS
              SELECT chid, 'anidb'::extlink_site AS site, l_anidb::text AS value FROM staff_hist WHERE l_anidb IS NOT NULL
    UNION ALL SELECT chid, 'wikidata',    l_wikidata::text  FROM staff_hist WHERE l_wikidata   IS NOT NULL
    UNION ALL SELECT chid, 'egs_creator', l_egs::text       FROM staff_hist WHERE l_egs        <> 0
    UNION ALL SELECT chid, 'anison',      l_anison::text    FROM staff_hist WHERE l_anison     <> 0
    UNION ALL SELECT chid, 'pixiv',       l_pixiv::text     FROM staff_hist WHERE l_pixiv      <> 0
    UNION ALL SELECT chid, 'vgmdb',       l_vgmdb::text     FROM staff_hist WHERE l_vgmdb      <> 0
    UNION ALL SELECT chid, 'discogs',     l_discogs::text   FROM staff_hist WHERE l_discogs    <> 0
    UNION ALL SELECT chid, 'mobygames',   l_mobygames::text FROM staff_hist WHERE l_mobygames  <> 0
    UNION ALL SELECT chid, 'bgmtv',       l_bgmtv::text     FROM staff_hist WHERE l_bgmtv      <> 0
    UNION ALL SELECT chid, 'imdb',        l_imdb::text      FROM staff_hist WHERE l_imdb       <> 0
    UNION ALL SELECT chid, 'wp',          l_wp              FROM staff_hist WHERE l_wp         <> ''
    UNION ALL SELECT chid, 'website',     l_site            FROM staff_hist WHERE l_site       <> ''
    UNION ALL SELECT chid, 'twitter',     l_twitter         FROM staff_hist WHERE l_twitter    <> ''
    UNION ALL SELECT chid, 'scloud',      l_scloud          FROM staff_hist WHERE l_scloud     <> ''
    UNION ALL SELECT chid, 'patreon',     l_patreon         FROM staff_hist WHERE l_patreon    <> ''
    UNION ALL SELECT chid, 'substar',     l_substar         FROM staff_hist WHERE l_substar    <> ''
    UNION ALL SELECT chid, 'youtube',     l_youtube         FROM staff_hist WHERE l_youtube    <> ''
    UNION ALL SELECT chid, 'instagram',   l_instagram       FROM staff_hist WHERE l_instagram  <> ''
    UNION ALL SELECT chid, 'deviantar',   l_deviantar       FROM staff_hist WHERE l_deviantar  <> ''
    UNION ALL SELECT chid, 'tumblr',      l_tumblr          FROM staff_hist WHERE l_tumblr     <> ''
    UNION ALL SELECT chid, 'vndb',        l_vndb::text      FROM staff_hist WHERE l_vndb       IS NOT NULL
    UNION ALL SELECT chid, 'mbrainz',     l_mbrainz::text   FROM staff_hist WHERE l_mbrainz    IS NOT NULL;

ANALYZE tmp_rhlinks, tmp_rlinks, tmp_shlinks, tmp_slinks;

INSERT INTO extlinks (site, value)
          SELECT site, value FROM tmp_rhlinks
    UNION SELECT site, value FROM tmp_rlinks
    UNION SELECT site, value FROM tmp_shlinks
    UNION SELECT site, value FROM tmp_slinks;

ANALYZE extlinks;

INSERT INTO releases_extlinks (id, c_site, link) SELECT r.id, r.site, e.id FROM tmp_rlinks r JOIN extlinks e ON e.site = r.site AND e.value = r.value;
INSERT INTO releases_extlinks_hist (chid, link) SELECT r.chid, e.id FROM tmp_rhlinks r JOIN extlinks e ON e.site = r.site AND e.value = r.value;

INSERT INTO staff_extlinks (id, c_site, link) SELECT r.id, r.site, e.id FROM tmp_slinks r JOIN extlinks e ON e.site = r.site AND e.value = r.value;
INSERT INTO staff_extlinks_hist (chid, link) SELECT r.chid, e.id FROM tmp_shlinks r JOIN extlinks e ON e.site = r.site AND e.value = r.value;

ANALYZE releases_extlinks, releases_extlinks_hist, staff_extlinks, staff_extlinks_hist;

--select site, count(*), avg(length(value)) from extlinks group by site;
--select c_site, count(*) from releases_extlinks group by c_site;
--select c_site, count(*) from releases_extlinks_hist group by c_site;
--select c_site, count(*) from staff_extlinks group by c_site;

DROP VIEW releasest, staff_aliast CASCADE;

ALTER TABLE releases
  DROP COLUMN l_toranoana,
  DROP COLUMN l_appstore,
  DROP COLUMN l_nintendo_jp,
  DROP COLUMN l_nintendo_hk,
  DROP COLUMN l_steam,
  DROP COLUMN l_digiket,
  DROP COLUMN l_melon,
  DROP COLUMN l_mg,
  DROP COLUMN l_getchu,
  DROP COLUMN l_getchudl,
  DROP COLUMN l_egs,
  DROP COLUMN l_erotrail,
  DROP COLUMN l_melonjp,
  DROP COLUMN l_gamejolt,
  DROP COLUMN l_animateg,
  DROP COLUMN l_freem,
  DROP COLUMN l_novelgam,
  DROP COLUMN website,
  DROP COLUMN l_dlsite,
  DROP COLUMN l_dlsiteen,
  DROP COLUMN l_gog,
  DROP COLUMN l_denpa,
  DROP COLUMN l_jlist,
  DROP COLUMN l_jastusa,
  DROP COLUMN l_itch,
  DROP COLUMN l_nutaku,
  DROP COLUMN l_googplay,
  DROP COLUMN l_fakku,
  DROP COLUMN l_freegame,
  DROP COLUMN l_playstation_jp,
  DROP COLUMN l_playstation_na,
  DROP COLUMN l_playstation_eu,
  DROP COLUMN l_playstation_hk,
  DROP COLUMN l_nintendo,
  DROP COLUMN l_gyutto,
  DROP COLUMN l_dmm,
  DROP COLUMN l_booth,
  DROP COLUMN l_patreonp,
  DROP COLUMN l_patreon,
  DROP COLUMN l_substar;

ALTER TABLE releases_hist
  DROP COLUMN l_toranoana,
  DROP COLUMN l_appstore,
  DROP COLUMN l_nintendo_jp,
  DROP COLUMN l_nintendo_hk,
  DROP COLUMN l_steam,
  DROP COLUMN l_digiket,
  DROP COLUMN l_melon,
  DROP COLUMN l_mg,
  DROP COLUMN l_getchu,
  DROP COLUMN l_getchudl,
  DROP COLUMN l_egs,
  DROP COLUMN l_erotrail,
  DROP COLUMN l_melonjp,
  DROP COLUMN l_gamejolt,
  DROP COLUMN l_animateg,
  DROP COLUMN l_freem,
  DROP COLUMN l_novelgam,
  DROP COLUMN website,
  DROP COLUMN l_dlsite,
  DROP COLUMN l_dlsiteen,
  DROP COLUMN l_gog,
  DROP COLUMN l_denpa,
  DROP COLUMN l_jlist,
  DROP COLUMN l_jastusa,
  DROP COLUMN l_itch,
  DROP COLUMN l_nutaku,
  DROP COLUMN l_googplay,
  DROP COLUMN l_fakku,
  DROP COLUMN l_freegame,
  DROP COLUMN l_playstation_jp,
  DROP COLUMN l_playstation_na,
  DROP COLUMN l_playstation_eu,
  DROP COLUMN l_playstation_hk,
  DROP COLUMN l_nintendo,
  DROP COLUMN l_gyutto,
  DROP COLUMN l_dmm,
  DROP COLUMN l_booth,
  DROP COLUMN l_patreonp,
  DROP COLUMN l_patreon,
  DROP COLUMN l_substar;

ALTER TABLE staff
  DROP COLUMN l_anidb,
  DROP COLUMN l_wikidata,
  DROP COLUMN l_egs,
  DROP COLUMN l_anison,
  DROP COLUMN l_pixiv,
  DROP COLUMN l_vgmdb,
  DROP COLUMN l_discogs,
  DROP COLUMN l_mobygames,
  DROP COLUMN l_bgmtv,
  DROP COLUMN l_imdb,
  DROP COLUMN l_wp,
  DROP COLUMN l_site,
  DROP COLUMN l_twitter,
  DROP COLUMN l_scloud,
  DROP COLUMN l_patreon,
  DROP COLUMN l_substar,
  DROP COLUMN l_youtube,
  DROP COLUMN l_instagram,
  DROP COLUMN l_deviantar,
  DROP COLUMN l_tumblr,
  DROP COLUMN l_vndb,
  DROP COLUMN l_mbrainz;

ALTER TABLE staff_hist
  DROP COLUMN l_anidb,
  DROP COLUMN l_wikidata,
  DROP COLUMN l_egs,
  DROP COLUMN l_anison,
  DROP COLUMN l_pixiv,
  DROP COLUMN l_vgmdb,
  DROP COLUMN l_discogs,
  DROP COLUMN l_mobygames,
  DROP COLUMN l_bgmtv,
  DROP COLUMN l_imdb,
  DROP COLUMN l_wp,
  DROP COLUMN l_site,
  DROP COLUMN l_twitter,
  DROP COLUMN l_scloud,
  DROP COLUMN l_patreon,
  DROP COLUMN l_substar,
  DROP COLUMN l_youtube,
  DROP COLUMN l_instagram,
  DROP COLUMN l_deviantar,
  DROP COLUMN l_tumblr,
  DROP COLUMN l_vndb,
  DROP COLUMN l_mbrainz;

UPDATE extlinks SET data = s.sku,  price = s.price, lastfetch = s.lastfetch, deadsince = s.deadsince FROM shop_denpa s WHERE extlinks.site = 'denpa' AND value = s.id;
UPDATE extlinks SET data = s.shop, price = s.price, lastfetch = s.lastfetch, deadsince = s.deadsince FROM shop_dlsite s WHERE extlinks.site = 'dlsite' AND value = s.id;
UPDATE extlinks SET data = s.slug, price = s.price, lastfetch = s.lastfetch, deadsince = s.deadsince FROM shop_jastusa s WHERE extlinks.site = 'jastusa' AND value = s.id;
UPDATE extlinks SET                price = s.price, lastfetch = s.lastfetch, deadsince = s.deadsince FROM shop_jlist s WHERE extlinks.site = 'jlist' AND value = s.id;
UPDATE extlinks SET data = case when r18 then null else '1' end, price = s.price, lastfetch = s.lastfetch, deadsince = s.deadsince FROM shop_mg s WHERE extlinks.site = 'mg' AND value = s.id::text;

DROP TABLE shop_denpa;
DROP TABLE shop_dlsite;
DROP TABLE shop_jastusa;
DROP TABLE shop_jlist;
DROP TABLE shop_mg;

\i sql/schema.sql
\i sql/func.sql
\i sql/editfunc.sql
\i sql/perms.sql

SELECT update_extlinks_cache(null);

CREATE OR REPLACE FUNCTION wikidata_extlink_insert() RETURNS trigger AS $$
BEGIN
  INSERT INTO wikidata (id) VALUES (NEW.value::int) ON CONFLICT (id) DO NOTHING;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER extlinks_wikidata_new AFTER INSERT ON extlinks FOR EACH ROW WHEN (NEW.site = 'wikidata') EXECUTE PROCEDURE wikidata_extlink_insert();

VACUUM FULL ANALYZE extlinks, releases, releases_hist, staff, staff_hist;
