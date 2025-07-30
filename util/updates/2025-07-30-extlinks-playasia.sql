ALTER TYPE extlink_site ADD VALUE 'playasia' AFTER 'pixiv';


INSERT INTO extlinks (site, value, data, price, lastfetch)
  SELECT 'playasia', regexp_replace(url, '.*/13/70([^?/]+).*', '\1'), regexp_replace(url, '.*\.com/([^/]+)/13.*', '\1'), price, lastfetch FROM shop_playasia;

-- This takes a while
DO $$
DECLARE x record; more bool := true;
BEGIN
  WHILE more LOOP
    more := false;
    FOR x IN
      SELECT r.id, array_agg(e.id) link
        FROM (SELECT gtin, regexp_replace(url, '.*/13/70([^?/]+).*', '\1') FROM shop_playasia) a(gtin, value)
        JOIN extlinks e ON e.site = 'playasia' AND e.value = a.value
        JOIN releases r ON r.gtin = a.gtin
       WHERE NOT r.hidden
         AND NOT EXISTS(SELECT 1 FROM releases_extlinks re WHERE re.id = r.id AND re.c_site = 'playasia')
       GROUP BY r.id
       LIMIT 50
    LOOP
      more := true;
      PERFORM edit_r_init(x.id, (SELECT MAX(rev) FROM changes WHERE itemid = x.id));
      INSERT INTO edit_releases_extlinks (link) SELECT * FROM unnest(x.link);
      UPDATE edit_revision SET requester = 'u1', comments = 'PlayAsia link based on JAN code lookup.';
      PERFORM edit_r_commit();
    END LOOP;
    COMMIT;
    PERFORM pg_sleep(1);
  END LOOP;
END$$;

DROP TABLE shop_playasia, shop_playasia_gtin;
