ALTER TYPE release_image_type ADD VALUE 'pkgside' AFTER 'pkgcontent';
ALTER TYPE release_image_type ADD VALUE 'pkgmed' AFTER 'pkgside';
ALTER TABLE releases_images      ADD COLUMN photo boolean NOT NULL DEFAULT FALSE;
ALTER TABLE releases_images_hist ADD COLUMN photo boolean NOT NULL DEFAULT FALSE;
\i sql/func.sql
\i sql/editfunc.sql
SELECT update_vncache(id) FROM vn WHERE c_image IS DISTINCT FROM image;
