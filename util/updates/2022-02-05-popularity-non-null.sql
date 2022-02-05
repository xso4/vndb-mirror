\i sql/func.sql
SELECT update_vnvotestats();
ALTER TABLE vn
    ALTER COLUMN c_popularity SET NOT NULL,
    ALTER COLUMN c_pop_rank SET NOT NULL,
    ALTER COLUMN c_popularity SET DEFAULT 0,
    ALTER COLUMN c_pop_rank SET DEFAULT 0;
