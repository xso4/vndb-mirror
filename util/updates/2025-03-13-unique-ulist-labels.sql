-- There are a few duplicated labels in the database, add a '(2)' marker to the higher-id one.
-- (This only works if a label has been duplicated at most once, which is fortunately always the case)
UPDATE ulist_labels a
   SET label = label || ' (2)'
 WHERE EXISTS(SELECT 1 FROM ulist_labels b WHERE a.uid = b.uid AND a.label = b.label AND a.id < b.id);

CREATE UNIQUE INDEX ulist_labels_uid_label ON ulist_labels (uid, label);
