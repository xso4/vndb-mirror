ALTER TABLE ulist_labels ADD CONSTRAINT ulist_labels_id_max CHECK(id < 256 OR uid IN('u87924', 'u177161', 'u179798', 'u240920'));
