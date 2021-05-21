ALTER TABLE tags_parents        ADD COLUMN main boolean NOT NULL DEFAULT false;
ALTER TABLE tags_parents_hist   ADD COLUMN main boolean NOT NULL DEFAULT false;
ALTER TABLE traits_parents      ADD COLUMN main boolean NOT NULL DEFAULT false;
ALTER TABLE traits_parents_hist ADD COLUMN main boolean NOT NULL DEFAULT false;
\i sql/editfunc.sql

UPDATE tags_parents tp        SET main = true WHERE NOT EXISTS(SELECT 1 FROM tags_parents        tp2 WHERE tp2.id   = tp.id   AND tp2.parent < tp.parent);
UPDATE tags_parents_hist tp   SET main = true WHERE NOT EXISTS(SELECT 1 FROM tags_parents_hist   tp2 WHERE tp2.chid = tp.chid AND tp2.parent < tp.parent);
UPDATE traits_parents tp      SET main = true WHERE NOT EXISTS(SELECT 1 FROM traits_parents      tp2 WHERE tp2.id   = tp.id   AND tp2.parent < tp.parent);
UPDATE traits_parents_hist tp SET main = true WHERE NOT EXISTS(SELECT 1 FROM traits_parents_hist tp2 WHERE tp2.chid = tp.chid AND tp2.parent < tp.parent);

-- Update the traits.group cache for consistency with the above selected 'main' flags.
WITH RECURSIVE childs (id, grp) AS (
    SELECT id, id FROM traits t WHERE NOT EXISTS(SELECT 1 FROM traits_parents tp WHERE tp.id = t.id)
    UNION ALL
    SELECT tp.id, childs.grp FROM childs JOIN traits_parents tp ON tp.parent = childs.id AND tp.main
) UPDATE traits SET "group" = grp FROM childs WHERE childs.id = traits.id AND "group" IS DISTINCT FROM grp AND grp <> childs.id;
