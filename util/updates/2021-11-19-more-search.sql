BEGIN;
\i sql/func.sql
ALTER TABLE releases DROP COLUMN c_search;
DROP FUNCTION search_gen(boolean,text[]);
ALTER TABLE releases    ADD COLUMN c_search text NOT NULL GENERATED ALWAYS AS (public.search_gen(ARRAY[title, original])) STORED;
ALTER TABLE producers   ADD COLUMN c_search text NOT NULL GENERATED ALWAYS AS (public.search_gen(ARRAY[name, original]::text[]||string_to_array(alias,E'\n'))) STORED;
ALTER TABLE chars       ADD COLUMN c_search text NOT NULL GENERATED ALWAYS AS (public.search_gen(ARRAY[name, original]::text[]||string_to_array(alias,E'\n'))) STORED;
ALTER TABLE staff_alias ADD COLUMN c_search text NOT NULL GENERATED ALWAYS AS (public.search_gen(ARRAY[name, original])) STORED;
COMMIT;
