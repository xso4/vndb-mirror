DROP FUNCTION edit_committed(integer, vndbid, integer);
\i sql/func.sql
\i sql/editfunc.sql

SELECT COUNT(*) FROM (SELECT edit_update_reachable(id) FROM chars c WHERE NOT hidden AND NOT EXISTS(SELECT 1 FROM chars_vns cv JOIN vn v ON v.id = cv.vid WHERE NOT v.hidden AND c.id = cv.id));
SELECT COUNT(*) FROM (SELECT edit_update_reachable(id) FROM releases r WHERE NOT hidden AND NOT EXISTS(SELECT 1 FROM releases_vn rv JOIN vn v ON v.id = rv.vid WHERE NOT v.hidden AND r.id = rv.id));
