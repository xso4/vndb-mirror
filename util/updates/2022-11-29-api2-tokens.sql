ALTER TYPE session_type ADD VALUE 'api2' AFTER 'api';

ALTER TABLE sessions
    ADD COLUMN notes text,
    ADD COLUMN listread boolean NOT NULL DEFAULT false;

\i sql/func.sql

DROP FUNCTION user_isvalidsession(vndbid, bytea, session_type);
