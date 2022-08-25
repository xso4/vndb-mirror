ALTER TABLE users_prefs ADD COLUMN customcss_csum      bigint NOT NULL DEFAULT 0;
-- '1' is not exactly a checksum, but it'll do fine for the first version.
UPDATE users_prefs SET customcss_csum = 1 WHERE customcss <> '';
