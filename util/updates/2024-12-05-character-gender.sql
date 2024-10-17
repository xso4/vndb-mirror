DROP VIEW charst CASCADE;

CREATE TYPE char_gender       AS ENUM ('', 'm', 'f', 'o', 'a');
ALTER TABLE chars
  ADD COLUMN gender       char_gender,
  ADD COLUMN spoil_gender char_gender;
ALTER TABLE chars_hist
  ADD COLUMN gender       char_gender,
  ADD COLUMN spoil_gender char_gender;

\i sql/schema.sql
\i sql/func.sql
\i sql/editfunc.sql
\i sql/perms.sql
