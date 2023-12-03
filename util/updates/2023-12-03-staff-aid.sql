ALTER TABLE staff      RENAME COLUMN aid TO main;
ALTER TABLE staff_hist RENAME COLUMN aid TO main;

ALTER TABLE staff DROP CONSTRAINT staff_aid_fkey;
ALTER TABLE staff                    ADD CONSTRAINT staff_main_fkey                    FOREIGN KEY (main)      REFERENCES staff_alias   (aid) DEFERRABLE INITIALLY DEFERRED;

DROP VIEW staff_aliast CASCADE;
\i sql/schema.sql
\i sql/func.sql
\i sql/editfunc.sql
\i sql/perms.sql
