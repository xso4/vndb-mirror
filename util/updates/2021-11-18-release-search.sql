CREATE EXTENSION unaccent;
\i sql/func.sql
ALTER TABLE releases ADD COLUMN c_search text NOT NULL GENERATED ALWAYS AS (public.search_gen(hidden, ARRAY[title, original])) STORED;
