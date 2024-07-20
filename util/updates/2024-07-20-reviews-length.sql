ALTER TABLE reviews ADD COLUMN length smallint NOT NULL GENERATED ALWAYS AS (CASE WHEN length(text) <= 800 THEN 0 WHEN length(text) <= 2500 THEN 1 ELSE 2 END) STORED;
ALTER TABLE reviews DROP COLUMN isfull;
\i sql/func.sql
