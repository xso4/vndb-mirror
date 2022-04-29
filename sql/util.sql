-- This file is for generic utility functions that do not depend on the data schema.
-- It should be loaded before schema.sql.


-- strip_bb_tags(text) - simple utility function to aid full-text searching
CREATE OR REPLACE FUNCTION strip_bb_tags(t text) RETURNS text AS $$
  SELECT regexp_replace(t, '\[(?:url=[^\]]+|/?(?:spoiler|quote|raw|code|url))\]', ' ', 'gi');
$$ LANGUAGE sql IMMUTABLE;

-- Wrapper around to_tsvector() and strip_bb_tags(), implemented in plpgsql and
-- with an associated cost function to make it opaque to the query planner and
-- ensure the query planner realizes that this function is _slow_.
CREATE OR REPLACE FUNCTION bb_tsvector(t text) RETURNS tsvector AS $$
BEGIN
  RETURN to_tsvector('english', public.strip_bb_tags(t));
END;
$$ LANGUAGE plpgsql IMMUTABLE COST 500;

-- BUG: Since this isn't a full bbcode parser, [spoiler] tags inside [raw] or [code] are still considered spoilers.
CREATE OR REPLACE FUNCTION strip_spoilers(t text) RETURNS text AS $$
  -- The website doesn't require the [spoiler] tag to be closed, the outer replace catches that case.
  SELECT regexp_replace(regexp_replace(t, '\[spoiler\].*?\[/spoiler\]', ' ', 'ig'), '\[spoiler\].*', ' ', 'i');
$$ LANGUAGE sql IMMUTABLE;


-- Assigns a score to the relevance of a substring match, intended for use in
-- an ORDER BY clause. Exact matches are ordered first, prefix matches after
-- that, and finally a normal substring match. Not particularly fast, but
-- that's to be expected of naive substring searches.
-- Pattern must be escaped for use as a LIKE pattern.
CREATE OR REPLACE FUNCTION substr_score(str text, pattern text) RETURNS integer AS $$
SELECT CASE
  WHEN str ILIKE      pattern      THEN 0
  WHEN str ILIKE      pattern||'%' THEN 1
  WHEN str ILIKE '%'||pattern||'%' THEN 2
  ELSE 3
END;
$$ LANGUAGE SQL;


-- Convenient function to match the first character of a string. Second argument must be lowercase 'a'-'z' or '0'.
-- Postgres can inline and partially evaluate this function into the query plan, so it's fairly efficient.
CREATE OR REPLACE FUNCTION match_firstchar(str text, chr text) RETURNS boolean AS $$
  SELECT CASE WHEN chr = '0'
         THEN (ascii(str) < 97 OR ascii(str) > 122) AND (ascii(str) < 65 OR ascii(str) > 90)
         ELSE ascii(str) IN(ascii(chr),ascii(upper(chr)))
         END;
$$ LANGUAGE SQL IMMUTABLE;


-- Helper function for search normalization
CREATE OR REPLACE FUNCTION search_norm_term(str text) RETURNS text AS $$
  SELECT regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
            translate(lower(public.unaccent(normalize(str, NFKC))), $s$@,_-‐.~～〜∼ー῀:[]()%+!?#$`♥★☆♪†「」『』【】・<>'$s$, 'a'), -- '
            '\s+', '', 'g'),
            '&', 'and', 'g'),
            'disc', 'disk', 'g'),
            'gray', 'grey', 'g'),
            'colour', 'color', 'g'),
            'senpai', 'sempai', 'g');
$$ LANGUAGE SQL IMMUTABLE;


CREATE OR REPLACE FUNCTION search_gen(terms text[]) RETURNS text AS $$
  SELECT coalesce(string_agg(t, ' '), '') FROM (
    SELECT t FROM (
      SELECT public.search_norm_term(t) FROM unnest(terms) x(t)
    ) x(t) WHERE t IS NOT NULL AND t <> '' GROUP BY t ORDER BY t
  ) x(t);
$$ LANGUAGE SQL IMMUTABLE;


-- Split a search query into LIKE patterns.
-- Supports double quoting for adjacent terms.
-- e.g. 'SEARCH que.ry "word here"' -> '{%search%,%query%,%wordhere%}'
--
-- Can be efficiently used as follows: c_search LIKE ALL (search_query('query here'))
CREATE OR REPLACE FUNCTION search_query(q text) RETURNS text[] AS $$
DECLARE
  tmp text;
  ret text[];
BEGIN
  ret := ARRAY[]::text[];
  LOOP
    q := regexp_replace(q, '^\s+', '');
    IF q = '' THEN EXIT;
    ELSIF q ~ '^"[^"]+"' THEN
      tmp := regexp_replace(q, '^"([^"]+)".*$', '\1', '');
      q := regexp_replace(q, '^"[^"]+"', '', '');
    ELSE
      tmp := regexp_replace(q, '^([^\s]+).*$', '\1', '');
      q := regexp_replace(q, '^[^\s]+', '', '');
    END IF;

    tmp := '%'||search_norm_term(tmp)||'%';
    IF length(tmp) > 2 AND NOT (ARRAY[tmp] <@ ret) THEN
      ret := array_append(ret, tmp);
    END IF;
  END LOOP;
  RETURN ret;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
