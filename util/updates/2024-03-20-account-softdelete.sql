CREATE TABLE email_optout (
  mail        uuid, -- hash_email()
  date        timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (mail)
);

ALTER TABLE users ALTER COLUMN username DROP NOT NULL;
ALTER TABLE audit_log ALTER COLUMN by_ip DROP NOT NULL;

\i sql/func.sql
\i sql/perms.sql
