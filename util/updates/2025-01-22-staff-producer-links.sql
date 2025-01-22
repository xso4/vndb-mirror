DROP VIEW staff_aliast CASCADE;
ALTER TABLE staff ADD COLUMN prod vndbid(p);
ALTER TABLE staff_hist ADD COLUMN prod vndbid(p);

CREATE        INDEX staff_prod             ON staff (prod) WHERE prod IS NOT NULL;
ALTER TABLE staff                    ADD CONSTRAINT staff_prod_fkey                    FOREIGN KEY (prod)      REFERENCES producers     (id);
ALTER TABLE staff_hist               ADD CONSTRAINT staff_hist_prod_fkey               FOREIGN KEY (prod)      REFERENCES producers     (id);

CREATE VIEW staff_aliast AS
    SELECT s.*, sa.aid, sa.name, sa.latin
         , ARRAY [ s.lang::text, COALESCE(sa.latin, sa.name)
                 , s.lang::text, sa.name ] AS title
         , COALESCE(sa.latin, sa.name) AS sorttitle
      FROM staff s
      JOIN staff_alias sa ON sa.id = s.id;
\i sql/func.sql
\i sql/editfunc.sql
\i sql/perms.sql
