\i sql/schema.sql
\i sql/tableattrs.sql
\i sql/editfunc.sql
\i sql/perms.sql


BEGIN;

CREATE OR REPLACE FUNCTION sup_from_notes(rid vndbid, sup vndbid[], newnotes text) RETURNS void AS $$
BEGIN
    PERFORM edit_r_init(rid, (SELECT MAX(rev) FROM changes WHERE itemid = rid));
    UPDATE edit_releases SET notes = newnotes;
    INSERT INTO edit_releases_supersedes (rid) SELECT unnest(sup);
    UPDATE edit_revision SET requester = 'u1', comments = 'Automatic extraction of supersedes links from notes.';
    PERFORM edit_r_commit();
END;
$$ LANGUAGE plpgsql;

WITH sup(id, rid) AS (
  SELECT s.id[1]::vndbid, r.id
    FROM releases r, regexp_matches(regexp_replace(notes, '^.*superseded by ((?:(?:\s|,|and)*r[0-9]+)+).*', '\1', 'i'), 'r[0-9]+', 'g') s(id)
   WHERE notes ~* 'superseded by r[0-9]+'
  UNION
  SELECT r.id, s.id[1]::vndbid
    FROM releases r, regexp_matches(regexp_replace(notes, '^.*supersedes ((?:(?:\s|,|and)*r[0-9]+)+).*', '\1', 'i'), 'r[0-9]+', 'g') s(id)
   WHERE notes ~* 'supersedes r[0-9]+'
), supf(id, rid) AS (
  SELECT DISTINCT *
    FROM sup
   WHERE EXISTS(SELECT 1 FROM releases WHERE id = sup.id AND NOT hidden)
     AND EXISTS(SELECT 1 FROM releases WHERE id = sup.rid AND NOT hidden)
) SELECT COUNT(*) FROM (
  SELECT sup_from_notes(r.id, array_agg(supf.rid), CASE WHEN r.id IN('r88071', 'r79683') THEN notes ELSE regexp_replace(r.notes, '\s*(superseded by|supersedes) ((?:(?:\s|,|and)*r[0-9]+)+)(?: \([^\)]+\))?(?:$|[,\.\n]+\s*)', '', 'ig') END)
    FROM supf JOIN releases r ON r.id = supf.id GROUP BY r.id
) x;

DROP FUNCTION sup_from_notes(vndbid, vndbid[], text);

COMMIT;
