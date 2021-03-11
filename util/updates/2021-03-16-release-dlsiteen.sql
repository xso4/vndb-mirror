-- Create a temporary copy of the DLsite English shop status information in case we want to revert.
CREATE TABLE shop_dlsiteen_old AS SELECT * FROM shop_dlsite WHERE id LIKE 'RE%';
DELETE FROM shop_dlsite WHERE id LIKE 'RE%';

CREATE OR REPLACE FUNCTION migrate_dlsiteen_to_dlsite(rid vndbid) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid));
    UPDATE edit_releases SET l_dlsite = regexp_replace(l_dlsiteen, '^RE', 'RJ');
    UPDATE edit_revision SET requester = 'u1', ip = '0.0.0.0', comments = 'DLsite English has been merged into the main DLsite, automatically migrating shop link.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;
SELECT migrate_dlsiteen_to_dlsite(id) FROM releases
 WHERE NOT hidden AND l_dlsite = '' AND l_dlsiteen <> ''
   AND NOT EXISTS(SELECT 1 FROM shop_dlsite WHERE id = l_dlsiteen AND deadsince < NOW()-'7 days'::interval);
DROP FUNCTION migrate_dlsiteen_to_dlsite(vndbid);
