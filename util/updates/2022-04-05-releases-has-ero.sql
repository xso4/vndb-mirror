ALTER TABLE releases      ADD COLUMN has_ero boolean NOT NULL DEFAULT FALSE;
ALTER TABLE releases_hist ADD COLUMN has_ero boolean NOT NULL DEFAULT FALSE;
UPDATE releases      SET has_ero = TRUE WHERE minage = 18;
UPDATE releases_hist SET has_ero = TRUE WHERE minage = 18;
\i sql/editfunc.sql
