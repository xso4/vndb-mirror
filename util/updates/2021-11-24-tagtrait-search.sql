ALTER TABLE tags   ADD COLUMN c_search text NOT NULL GENERATED ALWAYS AS (public.search_gen(ARRAY[name]::text[]||string_to_array(alias,E'\n'))) STORED;
ALTER TABLE traits ADD COLUMN c_search text NOT NULL GENERATED ALWAYS AS (public.search_gen(ARRAY[name]::text[]||string_to_array(alias,E'\n'))) STORED;
