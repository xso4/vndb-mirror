ALTER TABLE images ADD COLUMN uploader vndbid;
ALTER TABLE images                   ADD CONSTRAINT images_uploader_fkey               FOREIGN KEY (uploader)  REFERENCES users         (id) ON DELETE SET DEFAULT;


-- Attempt to find the original uploader of an image by finding the first
-- change that references it.
WITH cv (id, uid) AS (
    SELECT DISTINCT ON (v.image) v.image, c.requester
      FROM vn_hist v
      JOIN changes c ON c.id = v.chid
     WHERE v.image IS NOT NULL AND c.requester IS NOT NULL AND c.requester <> 'u1'
     ORDER BY v.image, v.chid
) UPDATE images SET uploader = uid FROM cv WHERE uploader IS NULL AND cv.id = images.id;

WITH sf (id, uid) AS (
    SELECT DISTINCT ON (v.scr) v.scr, c.requester
      FROM vn_screenshots_hist v
      JOIN changes c ON c.id = v.chid
     WHERE c.requester IS NOT NULL AND c.requester <> 'u1'
     ORDER BY v.scr, v.chid
) UPDATE images SET uploader = uid FROM sf WHERE uploader IS NULL AND sf.id = images.id;

WITH ch (id, uid) AS (
    SELECT DISTINCT ON (v.image) v.image, c.requester
      FROM chars_hist v
      JOIN changes c ON c.id = v.chid
     WHERE v.image IS NOT NULL AND c.requester IS NOT NULL AND c.requester <> 'u1'
     ORDER BY v.image, v.chid
) UPDATE images SET uploader = uid FROM ch WHERE uploader IS NULL AND ch.id = images.id;
