ALTER TABLE vn_length_votes ADD COLUMN speed smallint NOT NULL;
ALTER TABLE vn_length_votes ALTER COLUMN speed DROP DEFAULT;
ALTER TABLE vn_length_votes ADD COLUMN notes2 text NOT NULL DEFAULT '';
UPDATE vn_length_votes SET notes2 = notes;
ALTER TABLE vn_length_votes DROP COLUMN notes;
ALTER TABLE vn_length_votes RENAME COLUMN notes2 TO notes;
