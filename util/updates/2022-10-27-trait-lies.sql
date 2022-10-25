ALTER TABLE chars_traits      ADD COLUMN lie boolean NOT NULL DEFAULT false;
ALTER TABLE chars_traits_hist ADD COLUMN lie boolean NOT NULL DEFAULT false;
ALTER TABLE traits_chars      ADD COLUMN lie boolean NOT NULL DEFAULT false;
\i sql/editfunc.sql
\i sql/func.sql
