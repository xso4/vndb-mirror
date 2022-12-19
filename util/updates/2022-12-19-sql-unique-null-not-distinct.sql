DROP INDEX threads_boards_pkey;
CREATE UNIQUE INDEX threads_boards_pkey    ON threads_boards (tid,type,iid) NULLS NOT DISTINCT;

DROP INDEX vn_staff_pkey;
CREATE UNIQUE INDEX vn_staff_pkey          ON vn_staff (id, eid, aid, role) NULLS NOT DISTINCT;
DROP INDEX vn_staff_hist_pkey;
CREATE UNIQUE INDEX vn_staff_hist_pkey     ON vn_staff_hist (chid, eid, aid, role) NULLS NOT DISTINCT;

DROP INDEX chars_vns_pkey;
CREATE UNIQUE INDEX chars_vns_pkey         ON chars_vns (id, vid, rid) NULLS NOT DISTINCT;
DROP INDEX chars_vns_hist_pkey;
CREATE UNIQUE INDEX chars_vns_hist_pkey    ON chars_vns_hist (chid, vid, rid) NULLS NOT DISTINCT;
