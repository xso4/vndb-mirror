ALTER TYPE session_type ADD VALUE 'api';
DROP FUNCTION user_login(vndbid, bytea, bytea);
\i sql/func.sql
