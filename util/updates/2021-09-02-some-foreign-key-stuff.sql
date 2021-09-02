-- Add an ON UPDATE CASCADE clause to these contraints to simplify moving lists across users or VNs.
ALTER TABLE ulist_vns_labels         DROP CONSTRAINT ulist_vns_labels_uid_lbl_fkey;
ALTER TABLE ulist_vns_labels         DROP CONSTRAINT ulist_vns_labels_uid_vid_fkey;
ALTER TABLE ulist_vns_labels         ADD CONSTRAINT ulist_vns_labels_uid_lbl_fkey      FOREIGN KEY (uid,lbl)   REFERENCES ulist_labels  (uid,id) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE ulist_vns_labels         ADD CONSTRAINT ulist_vns_labels_uid_vid_fkey      FOREIGN KEY (uid,vid)   REFERENCES ulist_vns     (uid,vid) ON DELETE CASCADE ON UPDATE CASCADE;
