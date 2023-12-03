ALTER TABLE staff
  ADD COLUMN l_vgmdb     integer NOT NULL DEFAULT 0,
  ADD COLUMN l_discogs   integer NOT NULL DEFAULT 0,
  ADD COLUMN l_mobygames integer NOT NULL DEFAULT 0,
  ADD COLUMN l_bgmtv     integer NOT NULL DEFAULT 0,
  ADD COLUMN l_imdb      integer NOT NULL DEFAULT 0,
  ADD COLUMN l_vndb      vndbid,
  ADD COLUMN l_mbrainz   uuid,
  ADD COLUMN l_scloud    text NOT NULL DEFAULT '';
ALTER TABLE staff_hist
  ADD COLUMN l_vgmdb     integer NOT NULL DEFAULT 0,
  ADD COLUMN l_discogs   integer NOT NULL DEFAULT 0,
  ADD COLUMN l_mobygames integer NOT NULL DEFAULT 0,
  ADD COLUMN l_bgmtv     integer NOT NULL DEFAULT 0,
  ADD COLUMN l_imdb      integer NOT NULL DEFAULT 0,
  ADD COLUMN l_vndb      vndbid,
  ADD COLUMN l_mbrainz   uuid,
  ADD COLUMN l_scloud    text NOT NULL DEFAULT '';

DROP VIEW staff_aliast CASCADE;
\i sql/schema.sql
\i sql/editfunc.sql
\i sql/func.sql
\i sql/perms.sql
