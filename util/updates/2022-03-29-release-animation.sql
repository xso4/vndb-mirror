BEGIN;

CREATE DOMAIN animation AS smallint CHECK(value IS NULL OR value IN(0,1) OR ((value & (4+8+16+32)) > 0 AND (value & (256+512)) <> (256+512)));

ALTER TABLE releases ADD COLUMN ani_story_sp animation;
ALTER TABLE releases ADD COLUMN ani_story_cg animation;
ALTER TABLE releases ADD COLUMN ani_cutscene animation;
ALTER TABLE releases ADD COLUMN ani_ero_sp   animation;
ALTER TABLE releases ADD COLUMN ani_ero_cg   animation;
ALTER TABLE releases ADD COLUMN ani_bg       boolean;
ALTER TABLE releases ADD COLUMN ani_face     boolean;

ALTER TABLE releases_hist ADD COLUMN ani_story_sp animation;
ALTER TABLE releases_hist ADD COLUMN ani_story_cg animation;
ALTER TABLE releases_hist ADD COLUMN ani_cutscene animation;
ALTER TABLE releases_hist ADD COLUMN ani_ero_sp   animation;
ALTER TABLE releases_hist ADD COLUMN ani_ero_cg   animation;
ALTER TABLE releases_hist ADD COLUMN ani_bg       boolean;
ALTER TABLE releases_hist ADD COLUMN ani_face     boolean;

UPDATE releases      SET ani_story_sp = 0, ani_story_cg = 0, ani_face = false, ani_bg = false WHERE ani_story = 1;
UPDATE releases_hist SET ani_story_sp = 0, ani_story_cg = 0, ani_face = false, ani_bg = false WHERE ani_story = 1;
UPDATE releases      SET ani_ero_sp   = 0, ani_ero_cg   = 0 WHERE ani_ero   = 1;
UPDATE releases_hist SET ani_ero_sp   = 0, ani_ero_cg   = 0 WHERE ani_ero   = 1;

ALTER TABLE releases ADD CONSTRAINT releases_cutscene_check CHECK(ani_cutscene <> 0 AND (ani_cutscene & (256+512)) = 0);

\i sql/editfunc.sql
COMMIT;
