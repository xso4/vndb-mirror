BEGIN;
ALTER TABLE threads_posts
    DROP CONSTRAINT threads_posts_first_nonhidden,
    ALTER COLUMN hidden DROP NOT NULL,
    ALTER COLUMN hidden DROP DEFAULT,
    ALTER COLUMN hidden TYPE text USING case when hidden then '' else null end,
    ADD CONSTRAINT threads_posts_first_nonhidden CHECK(num > 1 OR hidden IS NULL);

ALTER TABLE reviews_posts
    ALTER COLUMN hidden DROP NOT NULL,
    ALTER COLUMN hidden DROP DEFAULT,
    ALTER COLUMN hidden TYPE text USING case when hidden then '' else null end;

\i sql/func.sql
COMMIT;

\i sql/triggers.sql
