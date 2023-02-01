CREATE TYPE item_info_type AS (title text, alttitle text, uid vndbid, hidden boolean, locked boolean);
\i sql/func.sql

-- Can be dropped after reloading all code.
--DROP FUNCTION item_info(vndbid, int);
