ALTER TABLE users_prefs_tags   ALTER COLUMN spoil DROP NOT NULL;
ALTER TABLE users_prefs_tags   ADD COLUMN color text;
ALTER TABLE users_prefs_traits ALTER COLUMN spoil DROP NOT NULL;
ALTER TABLE users_prefs_traits ADD COLUMN color text;

UPDATE users_prefs_tags   SET spoil = 0, color = 'standout' WHERE spoil = -1;
UPDATE users_prefs_traits SET spoil = 0, color = 'standout' WHERE spoil = -1;
