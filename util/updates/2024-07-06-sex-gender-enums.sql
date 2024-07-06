BEGIN;
CREATE TYPE char_sex           AS ENUM ('', 'm', 'f', 'b', 'n');
CREATE TYPE staff_gender       AS ENUM ('', 'm', 'f');

DROP VIEW charst CASCADE;
DROP VIEW staff_aliast CASCADE;

ALTER TABLE chars      RENAME gender       TO sex;
ALTER TABLE chars      RENAME spoil_gender TO spoil_sex;
ALTER TABLE chars_hist RENAME gender       TO sex;
ALTER TABLE chars_hist RENAME spoil_gender TO spoil_sex;

ALTER TABLE chars
  ALTER sex DROP DEFAULT,
  ALTER sex TYPE char_sex USING CASE WHEN sex = 'unknown' THEN '' ELSE sex::text END::char_sex,
  ALTER sex SET DEFAULT '',
  ALTER spoil_sex TYPE char_sex USING CASE WHEN spoil_sex = 'unknown' THEN '' ELSE spoil_sex::text END::char_sex;

ALTER TABLE chars_hist
  ALTER sex DROP DEFAULT,
  ALTER sex TYPE char_sex USING CASE WHEN sex = 'unknown' THEN '' ELSE sex::text END::char_sex,
  ALTER sex SET DEFAULT '',
  ALTER spoil_sex TYPE char_sex USING CASE WHEN spoil_sex = 'unknown' THEN '' ELSE spoil_sex::text END::char_sex;

ALTER TABLE staff
  ALTER gender DROP DEFAULT,
  ALTER gender TYPE staff_gender USING CASE WHEN gender = 'unknown' THEN '' ELSE gender::text END::staff_gender,
  ALTER gender SET DEFAULT '';

ALTER TABLE staff_hist
  ALTER gender DROP DEFAULT,
  ALTER gender TYPE staff_gender USING CASE WHEN gender = 'unknown' THEN '' ELSE gender::text END::staff_gender,
  ALTER gender SET DEFAULT '';

DROP TYPE gender;
COMMIT;

\i sql/schema.sql
\i sql/func.sql
\i sql/editfunc.sql
\i sql/perms.sql
