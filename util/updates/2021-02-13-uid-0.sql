-- columns that could still refer to uid=0
ALTER TABLE changes ALTER COLUMN requester DROP DEFAULT;
ALTER TABLE changes ALTER COLUMN requester DROP NOT NULL;
UPDATE      changes SET requester = NULL WHERE requester = 0;
ALTER TABLE tags ALTER COLUMN addedby DROP DEFAULT;
ALTER TABLE tags ALTER COLUMN addedby DROP NOT NULL;
UPDATE      tags SET addedby = NULL WHERE addedby = 0;
ALTER TABLE traits ALTER COLUMN addedby DROP DEFAULT;
ALTER TABLE traits ALTER COLUMN addedby DROP NOT NULL;
UPDATE      traits SET addedby = NULL WHERE addedby = 0;
DELETE FROM users WHERE id = 0;
