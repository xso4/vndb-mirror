ALTER TABLE vn_length_votes ADD COLUMN rid2 vndbid[] NOT NULL DEFAULT '{}';
UPDATE vn_length_votes SET rid2 = ARRAY[rid];
ALTER TABLE vn_length_votes DROP COLUMN rid;
ALTER TABLE vn_length_votes RENAME COLUMN rid2 TO rid;
