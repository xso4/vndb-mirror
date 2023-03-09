ALTER TABLE chars      ALTER COLUMN original DROP NOT NULL, ALTER COLUMN original DROP DEFAULT;
ALTER TABLE chars_hist ALTER COLUMN original DROP NOT NULL, ALTER COLUMN original DROP DEFAULT;
UPDATE chars      SET original = NULL WHERE original = '';
UPDATE chars_hist SET original = NULL WHERE original = '';

CREATE VIEW charst AS
    SELECT *
         , ARRAY [ c_lang::text, name
                 , c_lang::text, COALESCE(original, name) ] AS title
         , name AS sorttitle
      FROM chars;

\i sql/func.sql
\i sql/perms.sql
