CREATE TABLE engines ( -- List of VN engines, for use with release info
  id          serial PRIMARY KEY, -- [pub]
  c_ref       integer NOT NULL DEFAULT 0, -- [pub]
  state       smallint NOT NULL DEFAULT 0,
  name        text NOT NULL, -- [pub]
  description text NOT NULL DEFAULT '' -- [pub]
);

CREATE UNIQUE INDEX engines_name           ON engines (name);

INSERT INTO engines (name, c_ref) SELECT engine, count(*) FILTER (WHERE NOT hidden) FROM releases WHERE engine <> '' GROUP BY engine;
INSERT INTO engines (name) SELECT engine FROM releases_hist WHERE engine <> '' ON CONFLICT (name) DO NOTHING;

DROP VIEW releasest CASCADE;
DROP VIEW moe.releasest CASCADE;
DROP VIEW moe.releases CASCADE;

ALTER TABLE releases      ADD COLUMN nengine integer;
ALTER TABLE releases_hist ADD COLUMN nengine integer;
UPDATE releases      SET nengine = (SELECT id FROM engines WHERE name = engine) WHERE engine <> '';
UPDATE releases_hist SET nengine = (SELECT id FROM engines WHERE name = engine) WHERE engine <> '';
ALTER TABLE releases      DROP COLUMN engine;
ALTER TABLE releases_hist DROP COLUMN engine;
ALTER TABLE releases      RENAME COLUMN nengine TO engine;
ALTER TABLE releases_hist RENAME COLUMN nengine TO engine;

ALTER TABLE releases                 ADD CONSTRAINT releases_engine_fkey               FOREIGN KEY (engine)    REFERENCES engines       (id);
ALTER TABLE releases_hist            ADD CONSTRAINT releases_hist_engine_fkey          FOREIGN KEY (engine)    REFERENCES engines       (id);

\i sql/schema.sql
\i sql/func.sql
\i sql/perms.sql
