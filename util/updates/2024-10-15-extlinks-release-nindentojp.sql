DROP VIEW releasest CASCADE;

ALTER TABLE releases
  ALTER COLUMN l_nintendo_jp DROP DEFAULT,
  ALTER COLUMN l_nintendo_jp TYPE bigint USING (CASE WHEN l_nintendo_jp ~ '^D?[0-9]+$' THEN regexp_replace(l_nintendo_jp, '[^0-9]', '', 'g')::bigint ELSE 0 END),
  ALTER COLUMN l_nintendo_jp SET DEFAULT 0;
ALTER TABLE releases_hist
  ALTER COLUMN l_nintendo_jp DROP DEFAULT,
  ALTER COLUMN l_nintendo_jp TYPE bigint USING (CASE WHEN l_nintendo_jp ~ '^D?[0-9]+$' THEN regexp_replace(l_nintendo_jp, '[^0-9]', '', 'g')::bigint ELSE 0 END),
  ALTER COLUMN l_nintendo_jp SET DEFAULT 0;

\i sql/schema.sql
\i sql/func.sql
\i sql/editfunc.sql
\i sql/perms.sql
