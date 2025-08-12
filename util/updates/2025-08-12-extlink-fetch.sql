ALTER TABLE extlinks ADD COLUMN deadcount integer;
UPDATE extlinks SET deadcount = 1 WHERE deadsince IS NOT NULL;

CREATE TABLE extlinks_fetch (
  id      integer NOT NULL,
  date    timestamptz NOT NULL DEFAULT NOW(),
  dead    boolean NOT NULL,
  data    text,
  price   text,
  detail  jsonb
);
CREATE        INDEX extlinks_fetch_id      ON extlinks_fetch (id);
ALTER TABLE extlinks_fetch           ADD CONSTRAINT exlinks_fetch_id_fkey              FOREIGN KEY (id)        REFERENCES extlinks      (id) ON DELETE CASCADE;
