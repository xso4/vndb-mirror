ALTER TABLE vn_length_votes ADD COLUMN private boolean NOT NULL DEFAULT FALSE;
ALTER TABLE vn_length_votes ALTER COLUMN private DROP DEFAULT;
\i sql/func.sql
