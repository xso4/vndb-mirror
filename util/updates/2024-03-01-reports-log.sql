CREATE TABLE reports_log (
  date       timestamptz NOT NULL DEFAULT NOW(),
  id         integer NOT NULL,
  status     report_status NOT NULL,
  uid        vndbid,
  message    text NOT NULL
);

CREATE        INDEX reports_log_id         ON reports_log (id);

ALTER TABLE reports_log              ADD CONSTRAINT reports_log_id_fkey                FOREIGN KEY (id)        REFERENCES reports       (id);
ALTER TABLE reports_log              ADD CONSTRAINT reports_log_uid_fkey               FOREIGN KEY (uid)       REFERENCES users         (id) ON DELETE SET DEFAULT;

GRANT SELECT, INSERT                 ON reports_log              TO vndb_site;
