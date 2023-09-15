BEGIN;
ALTER TABLE quotes
    DROP CONSTRAINT quotes_pkey,
    DROP CONSTRAINT quotes_vid_fkey;
ALTER TABLE quotes RENAME TO quotes_old;

CREATE TABLE quotes (
  vid        vndbid NOT NULL,
  rand       real,
  approved   boolean NOT NULL DEFAULT FALSE,
  quote      text NOT NULL,
  PRIMARY KEY(vid, quote)
);

INSERT INTO quotes SELECT vid, NULL, TRUE, quote FROM quotes_old;

ALTER TABLE quotes                   ADD CONSTRAINT quotes_vid_fkey                    FOREIGN KEY (vid)       REFERENCES vn            (id);
CREATE        INDEX quotes_rand            ON quotes (rand) WHERE rand IS NOT NULL;

CREATE OR REPLACE FUNCTION quotes_rand_calc() RETURNS void AS $$
  WITH q(vid,quote) AS (
    SELECT vid, quote FROM quotes q WHERE approved AND EXISTS(SELECT 1 FROM vn v WHERE v.id = q.vid AND NOT v.hidden)
  ), r(vid,quote,rand) AS (
    SELECT vid, quote,
           -- 'rand' is chosen such that each VN has an equal probability to be selected, regardless of how many quotes it has.
           ((dense_rank() OVER (ORDER BY vid)) - 1)::real / (SELECT COUNT(DISTINCT vid) FROM q) +
           (percent_rank() OVER (PARTITION BY vid ORDER BY quote)) / (SELECT COUNT(DISTINCT vid)+1 FROM q)
      FROM q
  ), u AS (
    UPDATE quotes SET rand = NULL WHERE NOT EXISTS(SELECT 1 FROM r WHERE quotes.vid = r.vid AND quotes.quote = r.quote)
  ) UPDATE quotes SET rand = r.rand FROM r WHERE r.vid = quotes.vid AND r.quote = quotes.quote
$$ LANGUAGE SQL;

SELECT quotes_rand_calc();
COMMIT;

\i sql/perms.sql
