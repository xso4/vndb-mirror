WITH conv(id,ref,value,data) AS (
  SELECT id, c_ref
       , regexp_replace(value, '^.*id([0-9]+)$', '\1')
       , CASE WHEN value ~ '^[a-z]{2}/app' THEN regexp_replace(value, '^([a-z]{2})/.+$', '\1') ELSE '' END
    FROM extlinks
   WHERE site = 'appstore'
), uniq(id,value,data) AS (
  -- There are a few duplicate links after normalization. Merge them by
  -- preferring referenced links over historical and region-locked links over
  -- generic.
  SELECT DISTINCT ON (value) id, value, data FROM conv ORDER BY value, NOT ref, data = '', id
), dup(old,new) AS (
  SELECT o.id, n.id FROM conv o JOIN uniq n ON o.value = n.value WHERE o.id NOT IN(SELECT id FROM uniq)
), upd1 AS (
  UPDATE releases_extlinks_hist SET link = new FROM dup WHERE link = old
), upd2 AS (
  UPDATE releases_extlinks SET link = new FROM dup WHERE link = old
), merge(id, del, value, data) AS (
  SELECT id, false, value, data FROM uniq
  UNION ALL
  SELECT old, true, NULL, NULL FROM dup
) MERGE INTO extlinks USING merge ON extlinks.id = merge.id
  WHEN MATCHED AND del THEN DELETE
  WHEN MATCHED THEN UPDATE SET value = merge.value, data = merge.data;

SELECT update_extlinks_cache(NULL);

UPDATE extlinks SET queue = 'el-triage', nextfetch = NOW() WHERE site = 'appstore' AND c_ref;
