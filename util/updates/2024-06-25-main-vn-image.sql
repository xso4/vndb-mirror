ALTER TABLE vn_image_votes ADD COLUMN c_main       boolean NOT NULL DEFAULT false;

\i sql/func.sql

SELECT update_vn_image_votes(NULL,NULL);
