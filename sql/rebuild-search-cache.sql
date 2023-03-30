-- This is a maintenance script to update all rows in search_cache.
-- It should be run whenever the search normalization functions in func.sql are updated.

-- This script is intentionally slow and performs the updates in smaller
-- batches in order to avoid long-held locks, which may otherwise cause the
-- site to become unresponsive. It also tries to avoid table bloat by only
-- updating rows that need to be updated.

DO $$
DECLARE
  rows_per_transaction CONSTANT integer := 1000;
  sleep_seconds CONSTANT float := 1;
  i integer;
BEGIN
  -- chars
  FOR i IN SELECT n FROM generate_series(0, (SELECT MAX(vndbid_num(id)) FROM chars), rows_per_transaction) x(n)
  LOOP
    PERFORM update_search(vndbid('c', x)) FROM generate_series(i+1, i+rows_per_transaction) x(x);
    COMMIT;
    PERFORM pg_sleep(sleep_seconds);
  END LOOP;

  -- producers
  FOR i IN SELECT n FROM generate_series(0, (SELECT MAX(vndbid_num(id)) FROM producers), rows_per_transaction) x(n)
  LOOP
    PERFORM update_search(vndbid('p', x)) FROM generate_series(i+1, i+rows_per_transaction) x(x);
    COMMIT;
    PERFORM pg_sleep(sleep_seconds);
  END LOOP;

  -- vn
  FOR i IN SELECT n FROM generate_series(0, (SELECT MAX(vndbid_num(id)) FROM vn), rows_per_transaction) x(n)
  LOOP
    PERFORM update_search(vndbid('v', x)) FROM generate_series(i+1, i+rows_per_transaction) x(x);
    COMMIT;
    PERFORM pg_sleep(sleep_seconds);
  END LOOP;

  -- releases
  FOR i IN SELECT n FROM generate_series(0, (SELECT MAX(vndbid_num(id)) FROM releases), rows_per_transaction) x(n)
  LOOP
    PERFORM update_search(vndbid('r', x)) FROM generate_series(i+1, i+rows_per_transaction) x(x);
    COMMIT;
    PERFORM pg_sleep(sleep_seconds);
  END LOOP;

  -- staff
  FOR i IN SELECT n FROM generate_series(0, (SELECT MAX(vndbid_num(id)) FROM staff), rows_per_transaction) x(n)
  LOOP
    PERFORM update_search(vndbid('s', x)) FROM generate_series(i+1, i+rows_per_transaction) x(x);
    COMMIT;
    PERFORM pg_sleep(sleep_seconds);
  END LOOP;
END$$;

-- These tables are small enough
SELECT count(*) FROM (SELECT update_search(id) FROM tags) x;
SELECT count(*) FROM (SELECT update_search(id) FROM traits) x;

ANALYZE search_cache;
