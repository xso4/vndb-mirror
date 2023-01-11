ALTER TABLE sessions ADD COLUMN listwrite boolean NOT NULL DEFAULT false;
DROP FUNCTION user_api2_set_token(vndbid, vndbid, bytea, bytea, text, boolean);
\i sql/func.sql
