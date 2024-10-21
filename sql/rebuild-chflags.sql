-- Updates the changes.c_chflags column.
-- Should be run whenever the categories are changed.

CREATE OR REPLACE FUNCTION edit_chfields(itemid vndbid, chid integer) RETURNS text[] AS $$
  SELECT CASE
    WHEN vndbid_type(itemid) = 'v' THEN edit_v_chfields(chid)
    WHEN vndbid_type(itemid) = 'r' THEN edit_r_chfields(chid)
    WHEN vndbid_type(itemid) = 'p' THEN edit_p_chfields(chid)
    WHEN vndbid_type(itemid) = 'c' THEN edit_c_chfields(chid)
    WHEN vndbid_type(itemid) = 'd' THEN edit_d_chfields(chid)
    WHEN vndbid_type(itemid) = 'g' THEN edit_g_chfields(chid)
    WHEN vndbid_type(itemid) = 'i' THEN edit_i_chfields(chid)
    WHEN vndbid_type(itemid) = 's' THEN edit_s_chfields(chid)
    ELSE NULL
    END;
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION update_changes_chflags(xchid integer, xitemid vndbid, xrev integer) RETURNS void AS $$
  WITH n(v) AS (
    SELECT chflags_diff(
        edit_chfields(xitemid, xchid),
        edit_chfields(xitemid, CASE WHEN xrev = 1 THEN 0 ELSE (SELECT id FROM changes WHERE itemid = xitemid AND rev = xrev - 1) END)
    )
  ) UPDATE changes SET c_chflags = v FROM n WHERE id = xchid AND c_chflags <> v;
$$ LANGUAGE SQL;


-- Perform the update in batches, similar to rebuild-search-cache.sql
DO $$
DECLARE
  rows_per_transaction CONSTANT integer := 1000;
  sleep_seconds CONSTANT float := 1;
  i integer;
BEGIN
  FOR i IN SELECT n FROM generate_series(0, (SELECT MAX(id) FROM changes), rows_per_transaction) x(n)
  LOOP
    PERFORM update_changes_chflags(id, itemid, rev) FROM changes WHERE id BETWEEN i+1 AND i+rows_per_transaction;
    COMMIT;
    PERFORM pg_sleep(sleep_seconds);
  END LOOP;
END$$;
