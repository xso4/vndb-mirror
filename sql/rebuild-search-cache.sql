-- This is a maintenance script to update all 'c_search' cache columns.
-- It should be run whenever the search normalization functions in func.sql are updated.

-- This script is intentionally slow and performs the updates in smaller
-- batches in order to avoid long-held locks, which may otherwise cause the
-- site to become unresponsive. It also tries to avoid table bloat by only
-- updating rows that need to be updated.

-- I don't like how the c_search generated column expressions are repeated in
-- this script, but it is what it is.

DO $$
DECLARE
  rows_per_transaction CONSTANT integer := 1000;
  sleep_seconds CONSTANT float := 1;
  i integer;
BEGIN
  -- chars
  FOR i IN SELECT n FROM generate_series(0, (SELECT MAX(vndbid_num(id)) FROM chars), rows_per_transaction) x(n)
  LOOP
    UPDATE chars SET name = name
     WHERE id BETWEEN vndbid('c', i+1) AND vndbid('c', i+rows_per_transaction)
       AND c_search IS DISTINCT FROM search_gen(ARRAY[name, original]::text[]||string_to_array(alias,E'\n'));
    COMMIT;
    PERFORM pg_sleep(sleep_seconds);
  END LOOP;

  -- producers
  FOR i IN SELECT n FROM generate_series(0, (SELECT MAX(vndbid_num(id)) FROM producers), rows_per_transaction) x(n)
  LOOP
    UPDATE producers SET name = name
     WHERE id BETWEEN vndbid('p', i+1) AND vndbid('p', i+rows_per_transaction)
       AND c_search IS DISTINCT FROM search_gen(ARRAY[name, original]::text[]||string_to_array(alias,E'\n'));
    COMMIT;
    PERFORM pg_sleep(sleep_seconds);
  END LOOP;

  -- vn
  FOR i IN SELECT n FROM generate_series(0, (SELECT MAX(vndbid_num(id)) FROM vn), rows_per_transaction) x(n)
  LOOP
    WITH x(n, s) AS (SELECT id, search_gen_vn(id) FROM vn WHERE id BETWEEN vndbid('v', i+1) AND vndbid('v', i+rows_per_transaction))
    UPDATE vn SET c_search = s FROM x WHERE id = n AND c_search IS DISTINCT FROM s;
    COMMIT;
    PERFORM pg_sleep(sleep_seconds);
  END LOOP;

  -- releases
  FOR i IN SELECT n FROM generate_series(0, (SELECT MAX(vndbid_num(id)) FROM releases), rows_per_transaction) x(n)
  LOOP
    UPDATE releases SET title = title
     WHERE id BETWEEN vndbid('r', i+1) AND vndbid('r', i+rows_per_transaction)
       AND c_search IS DISTINCT FROM search_gen(ARRAY[title, original]);
    COMMIT;
    PERFORM pg_sleep(sleep_seconds);
  END LOOP;

  -- staff_alias
  FOR i IN SELECT n FROM generate_series(0, (SELECT MAX(aid) FROM staff_alias), rows_per_transaction) x(n)
  LOOP
    UPDATE staff_alias SET name = name
     WHERE aid BETWEEN i+1 AND i+rows_per_transaction
       AND c_search IS DISTINCT FROM search_gen(ARRAY[name, original]);
    COMMIT;
    PERFORM pg_sleep(sleep_seconds);
  END LOOP;
END$$;

-- These tables are small enough
UPDATE tags SET name = name WHERE c_search IS DISTINCT FROM search_gen(ARRAY[name]::text[]||string_to_array(alias,E'\n'));
UPDATE traits SET name = name WHERE c_search IS DISTINCT FROM search_gen(ARRAY[name]::text[]||string_to_array(alias,E'\n'));
