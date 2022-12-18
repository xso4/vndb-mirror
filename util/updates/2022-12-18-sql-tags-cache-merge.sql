DROP INDEX IF EXISTS tags_vn_direct_tag_vid;
ALTER TABLE tags_vn_direct ADD PRIMARY KEY (tag, vid);

DROP INDEX IF EXISTS tags_vn_inherit_tag_vid;
ALTER TABLE tags_vn_inherit ADD PRIMARY KEY (tag, vid);

\i sql/func.sql
\i sql/perms.sql
