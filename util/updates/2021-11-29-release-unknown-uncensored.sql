ALTER TABLE releases      ALTER COLUMN uncensored DROP NOT NULL, ALTER COLUMN uncensored DROP DEFAULT;
ALTER TABLE releases_hist ALTER COLUMN uncensored DROP NOT NULL, ALTER COLUMN uncensored DROP DEFAULT;
\i sql/editfunc.sql
UPDATE releases      SET uncensored = NULL WHERE minage <> 18;
UPDATE releases_hist SET uncensored = NULL WHERE minage <> 18;
