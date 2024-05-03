ALTER TABLE releases_images ADD COLUMN lang language;
ALTER TABLE releases_images_hist ADD COLUMN lang language;
\i sql/editfunc.sql
