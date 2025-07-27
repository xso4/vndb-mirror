ALTER TABLE extlinks
  ADD COLUMN nextfetch timestamptz,
  ADD COLUMN queue text;

DROP INDEX extlinks_wikidata_fetch;
CREATE        INDEX extlinks_queue_fetch   ON extlinks (queue, nextfetch) WHERE queue IS NOT NULL;

UPDATE extlinks SET queue = 'el-triage', nextfetch = NOW() WHERE c_ref AND site = 'wikidata';

\i sql/func.sql
\i sql/perms.sql
