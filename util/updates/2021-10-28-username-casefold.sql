ALTER TABLE users DROP CONSTRAINT users_username_key;
CREATE UNIQUE INDEX users_username_key     ON users (lower(username));
