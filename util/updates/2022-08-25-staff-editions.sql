ALTER TYPE credit_type ADD VALUE 'translator' AFTER 'director';
ALTER TYPE credit_type ADD VALUE 'editor' AFTER 'translator';
ALTER TYPE credit_type ADD VALUE 'qa' AFTER 'editor';

CREATE TABLE vn_editions (
  id         vndbid NOT NULL, -- [pub]
  lang       language, -- [pub]
  eid        smallint NOT NULL, -- [pub] (not stable across entry revisions)
  official   boolean NOT NULL DEFAULT TRUE, -- [pub]
  name       text NOT NULL, -- [pub]
  PRIMARY KEY(id, eid)
);

CREATE TABLE vn_editions_hist (
  chid       integer NOT NULL,
  lang       language,
  eid        smallint NOT NULL,
  official   boolean NOT NULL DEFAULT TRUE,
  name       text NOT NULL,
  PRIMARY KEY(chid, eid)
);

ALTER TABLE vn_staff ADD COLUMN eid smallint;
ALTER TABLE vn_staff DROP CONSTRAINT vn_staff_pkey;
CREATE UNIQUE INDEX vn_staff_pkey ON vn_staff (id, COALESCE(eid,-1::smallint), aid, role);

ALTER TABLE vn_staff_hist ADD COLUMN eid smallint;
ALTER TABLE vn_staff_hist DROP CONSTRAINT vn_staff_hist_pkey;
CREATE UNIQUE INDEX vn_staff_hist_pkey ON vn_staff_hist (chid, COALESCE(eid,-1::smallint), aid, role);

ALTER TABLE vn_staff DROP CONSTRAINT vn_staff_id_fkey;
ALTER TABLE vn_staff_hist DROP CONSTRAINT vn_staff_hist_chid_fkey;

ALTER TABLE vn_staff                 ADD CONSTRAINT vn_staff_id_eid_fkey               FOREIGN KEY (id,eid)    REFERENCES vn_editions   (id,eid) DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE vn_staff_hist            ADD CONSTRAINT vn_staff_hist_chid_eid_fkey        FOREIGN KEY (chid,eid)  REFERENCES vn_editions_hist (chid,eid) DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE users_prefs
    ADD COLUMN staffed_langs       language[],
    ADD COLUMN staffed_olang       boolean NOT NULL DEFAULT true,
    ADD COLUMN staffed_unoff       boolean NOT NULL DEFAULT false;

\i sql/editfunc.sql
\i sql/perms.sql
