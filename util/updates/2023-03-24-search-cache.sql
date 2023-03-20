-- Part one, can be done while the site is running old code

CREATE EXTENSION pg_trgm;

CREATE TABLE search_cache (
    id    vndbid NOT NULL,
    subid integer, -- only for staff_alias.id at the moment
    prio  smallint NOT NULL, -- 1 for indirect titles, 2 for aliases, 3 for main titles
    label text NOT NULL COLLATE "C"
) PARTITION BY RANGE(id);

CREATE TABLE search_cache_v PARTITION OF search_cache FOR VALUES FROM ('v1') TO (vndbid_max('v'));
CREATE TABLE search_cache_r PARTITION OF search_cache FOR VALUES FROM ('r1') TO (vndbid_max('r'));
CREATE TABLE search_cache_c PARTITION OF search_cache FOR VALUES FROM ('c1') TO (vndbid_max('c'));
CREATE TABLE search_cache_p PARTITION OF search_cache FOR VALUES FROM ('p1') TO (vndbid_max('p'));
CREATE TABLE search_cache_s PARTITION OF search_cache FOR VALUES FROM ('s1') TO (vndbid_max('s'));
CREATE TABLE search_cache_g PARTITION OF search_cache FOR VALUES FROM ('g1') TO (vndbid_max('g'));
CREATE TABLE search_cache_i PARTITION OF search_cache FOR VALUES FROM ('i1') TO (vndbid_max('i'));

CREATE INDEX search_cache_id ON search_cache (id);
CREATE INDEX search_cache_label ON search_cache USING GIN (label gin_trgm_ops);

\i sql/perms.sql
\i sql/func.sql
\i sql/rebuild-search-cache.sql


-- Part two, can be done after the site has been reloaded with the new code

ALTER TABLE chars       DROP COLUMN c_search CASCADE;
ALTER TABLE producers   DROP COLUMN c_search CASCADE;
ALTER TABLE releases    DROP COLUMN c_search CASCADE;
ALTER TABLE staff_alias DROP COLUMN c_search CASCADE;
ALTER TABLE tags        DROP COLUMN c_search CASCADE;
ALTER TABLE traits      DROP COLUMN c_search CASCADE;
ALTER TABLE vn          DROP COLUMN c_search CASCADE;

\i sql/schema.sql
\i sql/func.sql
\i sql/perms.sql

DROP FUNCTION search_gen_vn(vndbid);
DROP FUNCTION search_gen_release(vndbid);
DROP FUNCTION search_gen(text[]);
