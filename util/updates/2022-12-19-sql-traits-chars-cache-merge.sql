DROP INDEX traits_chars_tid;
ALTER TABLE traits_chars ADD PRIMARY KEY (tid, cid);
CREATE INDEX traits_chars_cid ON traits_chars (cid);
\i sql/func.sql
\i sql/perms.sql
