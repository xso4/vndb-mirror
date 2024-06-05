CREATE TABLE vn_image_votes (
  vid        vndbid NOT NULL,
  uid        vndbid NOT NULL,
  img        vndbid NOT NULL,
  date       timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY(vid, uid, img)
);

ALTER TABLE vn_image_votes           ADD CONSTRAINT vn_image_votes_vid_fkey            FOREIGN KEY (vid)       REFERENCES vn            (id);
ALTER TABLE vn_image_votes           ADD CONSTRAINT vn_image_votes_uid_fkey            FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;
ALTER TABLE vn_image_votes           ADD CONSTRAINT vn_image_votes_img_fkey            FOREIGN KEY (img)       REFERENCES images        (id) ON DELETE CASCADE;

GRANT SELECT, INSERT, UPDATE, DELETE ON vn_image_votes           TO vndb_site;
