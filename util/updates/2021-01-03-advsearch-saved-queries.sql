CREATE TABLE saved_queries (
    uid   integer NOT NULL,
    name  text NOT NULL,
    qtype dbentry_type NOT NULL,
    query text NOT NULL, -- compact encoded form
    PRIMARY KEY(uid, qtype, name)
);

ALTER TABLE saved_queries            ADD CONSTRAINT saved_queries_uid_fkey             FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE CASCADE;
GRANT SELECT, INSERT, UPDATE, DELETE ON saved_queries            TO vndb_site;
