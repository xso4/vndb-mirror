BEGIN;
ALTER TABLE quotes
    ADD COLUMN hidden boolean NOT NULL DEFAULT FALSE,
    ADD COLUMN added timestamptz NOT NULL DEFAULT NOW();
UPDATE quotes SET hidden = true WHERE state = 2;
ALTER TABLE quotes DROP COLUMN state;

CREATE INDEX quotes_addedby ON quotes (addedby);

COMMIT;

\i sql/func.sql
