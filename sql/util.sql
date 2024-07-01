-- This file is for generic utility functions that do not depend on the data schema.
-- It should be loaded before schema.sql.


-- Add an element in the correct position to an already sorted array.
-- The array is not modified if the element already exists.
-- This function is probably quite slow, don't use in contexts where performance matters.
CREATE OR REPLACE FUNCTION array_set(arr anycompatiblearray, elem anycompatible) RETURNS anycompatiblearray AS $$
DECLARE
  ret arr%TYPE;
  e elem%TYPE;
  added boolean := false;
BEGIN
  FOREACH e IN ARRAY arr LOOP
    IF e = elem THEN RETURN arr;
    ELSIF added or e < elem THEN ret := ret || e;
    ELSE
      ret := ret || elem || e;
      added := true;
    END IF;
  END LOOP;
  RETURN CASE WHEN added THEN ret ELSE ret || elem END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Some tests.
--SELECT array_set(ARRAY[1,2,3,8], 9) = ARRAY[1,2,3,8,9]
--     , array_set(ARRAY[1,2,3,8], 0) = ARRAY[0,1,2,3,8]
--     , array_set(ARRAY[1,2,3,8], 2) = ARRAY[1,2,3,8]
--     , array_set(ARRAY[1,2,3,8], 8) = ARRAY[1,2,3,8]
--     , array_set(ARRAY[1,2,3,8], 5) = ARRAY[1,2,3,5,8]
--     , array_set(ARRAY[8,3,2,1], 3) = ARRAY[8,3,2,1]    -- Also works on unsorted arrays
--     , array_set(ARRAY[8,3,2,1], 5) = ARRAY[5,8,3,2,1]; -- But then the output is also unsorted



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
            translate(lower(public.unaccent(normalize(translate(str, '™©®', ''), NFKC))), $s$@,_-‐.~～〜∼ー῀:[]()%+!?#$`♥★☆♪†「」『』【】・<>'$s$, 'a'), -- '
            '\s+', '', 'g'),
            '&', 'and', 'g'),
            'disc', 'disk', 'g'),
            'gray', 'grey', 'g'),
            'colour', 'color', 'g'),
            'senpai', 'sempai', 'g');
$$ LANGUAGE SQL IMMUTABLE;


-- Split a search query into LIKE patterns.
-- Supports double quoting for adjacent terms.
-- e.g. 'SEARCH que.ry "word here"' -> '{%search%,%query%,%wordhere%}'
--
-- Can be efficiently used as follows: label LIKE ALL (search_query('query here'))
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


-- E-mail normalization, used for account lookup and to provide a strong account opt-out.
-- Totally imperfect, of course, but it catches common cases.
-- Based on https://dev.maxmind.com/minfraud/normalizing-email-addresses-for-minfraud
-- except this function assumes the address has already been validated.
CREATE OR REPLACE FUNCTION norm_email(email text) RETURNS text AS $$
  WITH n1 (u,d) AS (
    SELECT lower(regexp_replace(email, '^(.+)@.+$', '\1')),
           lower(regexp_replace(email, '^.+@(.+)$', '\1'))
  ), n2 (u,d) AS (
    SELECT u, CASE WHEN d = 'googlemail.com' THEN 'gmail.com'
              WHEN d IN('pm.me', 'proton.me') THEN 'protonmail.com'
              WHEN d IN('yandex.by', 'yandex.com', 'yandex.kz', 'yandex.ua', 'ya.ru') THEN 'yandex.ru'
              ELSE d END FROM n1
  ), n3 (u,d) AS (
    SELECT CASE WHEN d IN('myyahoo.com', 'ymail.com', 'y7mail.com') OR d ~ '^yahoo.(ca|cl|cn|co|co\.id|co\.il|co\.in|co\.jp|co\.kr|com\.ar|com\.au|com\.br|com\.cn|com\.hk|com\.mx|com\.my|com\.ph|com\.sg|com\.tr|com\.tw|com\.vn|co\.nz|co\.th|co\.uk|co\.za|de|dk|es|fr|gr|hu|ie|in|it|ne\.jp|nl|no|pl|ro|se)$'
           THEN regexp_replace(u, '-.*$', '')
           ELSE regexp_replace(u, '\+.*$', '')
           END, d FROM n2
  ), n4 (u,d) AS (
    SELECT CASE WHEN d = 'gmail.com' THEN regexp_replace(u, '\.', '', 'g') ELSE u END, d FROM n3
  ) SELECT regexp_replace(u || '@' || d, -- https://www.fastmail.com/about/ourdomains/
      '^.+@(.+)\.(123mail\.org|150mail\.com|150ml\.com|16mail\.com|2-mail\.com|4email\.net|50mail\.com|airpost\.net|allmail\.net|cluemail\.com|elitemail\.org|emailcorner\.net|emailengine\.net|emailengine\.org|emailgroups\.net|emailplus\.org|emailuser\.net|eml\.cc|f-m\.fm|fast-email\.com|fast-mail\.org|fastem\.com|fastemailer\.com|fastest\.cc|fastimap\.com|fastmail\.cn|fastmail\.co\.uk|fastmail\.com|fastmail\.com\.au|fastmail\.de|fastmail\.es|fastmail\.fm|fastmail\.fr|fastmail\.im|fastmail\.in|fastmail\.jp|fastmail\.mx|fastmail\.net|fastmail\.nl|fastmail\.org|fastmail\.se|fastmail\.to|fastmail\.tw|fastmail\.uk|fastmailbox\.net|fastmessaging\.com|fea\.st|fmail\.co\.uk|fmailbox\.com|fmgirl\.com|fmguy\.com|ftml\.net|hailmail\.net|imap-mail\.com|imap\.cc|imapmail\.org|inoutbox\.com|internet-e-mail\.com|internet-mail\.org|internetemails\.net|internetmailing\.net|jetemail\.net|justemail\.net|letterboxes\.org|mail-central\.com|mail-page\.com|mailas\.com|mailbolt\.com|mailc\.net|mailcan\.com|mailforce\.net|mailhaven\.com|mailingaddress\.org|mailite\.com|mailmight\.com|mailnew\.com|mailsent\.net|mailservice\.ms|mailup\.net|mailworks\.org|ml1\.net|mm\.st|myfastmail\.com|mymacmail\.com|nospammail\.net|ownmail\.net|petml\.com|postinbox\.com|postpro\.net|proinbox\.com|promessage\.com|realemail\.net|reallyfast\.biz|reallyfast\.info|rushpost\.com|sent\.as|sent\.at|sent\.com|speedpost\.net|speedymail\.org|ssl-mail\.com|swift-mail\.com|the-fastest\.net|the-quickest\.com|theinternetemail\.com|veryfast\.biz|veryspeedy\.net|warpmail\.net|xsmail\.com|yepmail\.net|your-mail\.com)$', '\1@\2')
     FROM n4
$$ LANGUAGE SQL IMMUTABLE;

--SELECT norm_email('T.E.S.T+alias+2@GoogleMail.com') = 'test@gmail.com'
--     , norm_email('hello-alias-2@yahoo.co.jp') = 'hello@yahoo.co.jp'
--     , norm_email('somename@hello.4email.net') = 'hello@4email.net';

CREATE OR REPLACE FUNCTION hash_email(email text) RETURNS uuid LANGUAGE SQL IMMUTABLE RETURN md5(norm_email(email))::uuid;
