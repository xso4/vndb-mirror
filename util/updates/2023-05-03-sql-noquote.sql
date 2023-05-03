ALTER TABLE chars          RENAME COLUMN "desc" TO description;
ALTER TABLE chars_hist     RENAME COLUMN "desc" TO description;
ALTER TABLE producers      RENAME COLUMN "desc" TO description;
ALTER TABLE producers_hist RENAME COLUMN "desc" TO description;
ALTER TABLE staff          RENAME COLUMN "desc" TO description;
ALTER TABLE staff_hist     RENAME COLUMN "desc" TO description;
ALTER TABLE vn             RENAME COLUMN "desc" TO description;
ALTER TABLE vn_hist        RENAME COLUMN "desc" TO description;
ALTER TABLE traits         RENAME COLUMN "group" TO gid;
ALTER TABLE traits         RENAME COLUMN "order" TO gorder;
ALTER TABLE traits_hist    RENAME COLUMN "order" TO gorder;

ALTER TABLE traits DROP CONSTRAINT traits_group_fkey;
ALTER TABLE traits ADD CONSTRAINT traits_gid_fkey FOREIGN KEY (gid) REFERENCES traits (id);

DROP VIEW charst CASCADE;
DROP VIEW producerst CASCADE;
DROP VIEW staff_aliast CASCADE;
DROP VIEW vnt CASCADE;
\i sql/schema.sql
\i sql/func.sql
\i sql/editfunc.sql
\i sql/perms.sql
