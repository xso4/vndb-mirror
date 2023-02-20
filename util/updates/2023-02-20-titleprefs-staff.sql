ALTER TABLE staff_alias      ALTER COLUMN original DROP NOT NULL, ALTER COLUMN original DROP DEFAULT;
ALTER TABLE staff_alias_hist ALTER COLUMN original DROP NOT NULL, ALTER COLUMN original DROP DEFAULT;
UPDATE staff_alias      SET original = null WHERE original = '';
UPDATE staff_alias_hist SET original = null WHERE original = '';

CREATE VIEW staff_aliast AS
           -- Everything from 'staff', except 'aid' is renamed to 'main'
    SELECT s.id, s.gender, s.lang, s.l_anidb, s.l_wikidata, s.l_pixiv, s.locked, s.hidden, s."desc", s.l_wp, s.l_site, s.l_twitter, s.aid AS main
         , sa.aid, sa.name, sa.original
         , ARRAY [ s.lang::text, sa.name
                 , s.lang::text, COALESCE(sa.original, sa.name) ] AS title
         , sa.name AS sorttitle
      FROM staff s
      JOIN staff_alias sa ON sa.id = s.id;

\i sql/editfunc.sql
\i sql/func.sql
\i sql/perms.sql
