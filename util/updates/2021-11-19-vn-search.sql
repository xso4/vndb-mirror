DROP TRIGGER vn_vnsearch_notify ON vn;
DROP FUNCTION vn_vnsearch_notify();
\i sql/func.sql

-- Warning: slow
\timing
UPDATE vn SET c_search = search_gen_vn(id);
