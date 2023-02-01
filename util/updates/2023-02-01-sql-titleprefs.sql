\i sql/schema.sql

-- The old JSON structure is messy; the same language may be listed multiple
-- times and original language isn't always present or the last option. This
-- function attempts a clean conversion, where the preference is the same but
-- without the weirdness.
CREATE OR REPLACE FUNCTION json2titleprefs(title_langs jsonb, alttitle_langs jsonb) RETURNS titleprefs AS $$
  WITH t_parsed (rank, lang, latin, prio, official) AS (
    -- Parse, add rank & prio
    SELECT row_number() OVER(ROWS CURRENT ROW), lang, COALESCE(latin, false)
         , CASE WHEN original IS NOT DISTINCT FROM true THEN 3 WHEN official IS NOT DISTINCT FROM true THEN 2 ELSE 1 END
         , CASE WHEN original IS NOT DISTINCT FROM true THEN NULL ELSE COALESCE(official, false) END
      FROM jsonb_to_recordset(COALESCE(title_langs, '[{"latin":true}]'))
        AS x(lang language, latin bool, official bool, original bool)
  ), t (rank, lang, latin, official) AS (
    -- Filter, remove duplicates and re-rank
    SELECT CASE WHEN lang IS NULL THEN NULL ELSE row_number() OVER(ORDER BY rank) END, lang, latin, official
      FROM t_parsed x
     WHERE rank <= COALESCE((SELECT MIN(rank) FROM t_parsed WHERE lang IS NULL), 10)
       AND NOT EXISTS(SELECT 1 FROM t_parsed y WHERE x.lang = y.lang AND y.rank < x.rank AND y.prio <= x.prio)

    -- Same, for alttitle
  ), a_parsed (rank, lang, latin, prio, official) AS (
    SELECT row_number() OVER(ROWS CURRENT ROW), lang, COALESCE(latin, false)
         , CASE WHEN original IS NOT DISTINCT FROM true THEN 3 WHEN official IS NOT DISTINCT FROM true THEN 2 ELSE 1 END
         , CASE WHEN original IS NOT DISTINCT FROM true THEN NULL ELSE COALESCE(official, false) END
      FROM jsonb_to_recordset(alttitle_langs)
        AS x(lang language, latin bool, official bool, original bool)
  ), a (rank, lang, latin, official) AS (
    SELECT CASE WHEN lang IS NULL THEN NULL ELSE row_number() OVER(ORDER BY rank) END, lang, latin, official
      FROM a_parsed x
     WHERE rank <= COALESCE((SELECT MIN(rank) FROM a_parsed WHERE lang IS NULL), 10)
       AND NOT EXISTS(SELECT 1 FROM a_parsed y WHERE x.lang = y.lang AND y.rank < x.rank AND y.prio <= x.prio)

  ) SELECT ROW(
      (SELECT lang FROM t WHERE rank = 1)
    , (SELECT lang FROM t WHERE rank = 2)
    , (SELECT lang FROM t WHERE rank = 3)
    , (SELECT lang FROM t WHERE rank = 4)
    , (SELECT lang FROM a WHERE rank = 1)
    , (SELECT lang FROM a WHERE rank = 2)
    , (SELECT lang FROM a WHERE rank = 3)
    , (SELECT lang FROM a WHERE rank = 4)
    , COALESCE((SELECT latin FROM t WHERE rank = 1), false)
    , COALESCE((SELECT latin FROM t WHERE rank = 2), false)
    , COALESCE((SELECT latin FROM t WHERE rank = 3), false)
    , COALESCE((SELECT latin FROM t WHERE rank = 4), false)
    , COALESCE((SELECT latin FROM t WHERE lang IS NULL), false)
    , COALESCE((SELECT latin FROM a WHERE rank = 1), false)
    , COALESCE((SELECT latin FROM a WHERE rank = 2), false)
    , COALESCE((SELECT latin FROM a WHERE rank = 3), false)
    , COALESCE((SELECT latin FROM a WHERE rank = 4), false)
    , COALESCE((SELECT latin FROM a WHERE lang IS NULL), false)
    , (SELECT official FROM t WHERE rank = 1)
    , (SELECT official FROM t WHERE rank = 2)
    , (SELECT official FROM t WHERE rank = 3)
    , (SELECT official FROM t WHERE rank = 4)
    , (SELECT official FROM a WHERE rank = 1)
    , (SELECT official FROM a WHERE rank = 2)
    , (SELECT official FROM a WHERE rank = 3)
    , (SELECT official FROM a WHERE rank = 4)
    )::titleprefs
$$ LANGUAGE SQL IMMUTABLE;


ALTER TABLE users_prefs ADD COLUMN titles titleprefs;
UPDATE users_prefs SET titles = json2titleprefs(title_langs, alttitle_langs) WHERE title_langs IS NOT NULL OR alttitle_langs IS NOT NULL;
