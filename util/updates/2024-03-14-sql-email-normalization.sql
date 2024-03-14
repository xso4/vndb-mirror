\i sql/util.sql

DROP INDEX users_shadow_mail;
CREATE        INDEX users_shadow_mail      ON users_shadow (hash_email(mail));

DROP FUNCTION user_emailtoid(text);
DROP FUNCTION user_resetpass(text, bytea);

\i sql/func.sql
