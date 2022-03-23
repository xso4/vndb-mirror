BEGIN;
ALTER TABLE vn_length_votes ALTER COLUMN speed DROP NOT NULL;
UPDATE vn_length_votes SET speed = NULL WHERE ignore;
ALTER TABLE vn_length_votes DROP COLUMN ignore;
COMMIT;
\i sql/func.sql
