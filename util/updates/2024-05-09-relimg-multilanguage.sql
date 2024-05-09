ALTER TABLE releases_images      ALTER COLUMN lang TYPE language[] USING CASE WHEN lang IS NULL THEN NULL ELSE ARRAY[lang] END;
ALTER TABLE releases_images_hist ALTER COLUMN lang TYPE language[] USING CASE WHEN lang IS NULL THEN NULL ELSE ARRAY[lang] END;
\i sql/func.sql
