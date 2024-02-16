DROP TABLE nnm;
CREATE TABLE nnm (
  id      int NOT NULL DEFAULT (random()*(1::bigint << 31))::int,
  date    timestamptz NOT NULL DEFAULT NOW(),
  color   text,
  message text NOT NULL,
  ip      ipinfo,
  uid     vndbid
);
CREATE INDEX nnm_date ON nnm (date);
GRANT SELECT, INSERT ON TABLE nnm TO vndb_site;
