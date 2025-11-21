ALTER TABLE users ADD COLUMN notifyopts integer NOT NULL DEFAULT 44694140;

UPDATE users SET notifyopts = notifyopts | 2 WHERE notify_announce;
UPDATE users SET notifyopts = notifyopts & ~(3::integer << ( 3*2)) WHERE NOT notify_dbedit;
UPDATE users SET notifyopts = notifyopts & ~(3::integer << ( 9*2)) WHERE NOT notify_post;
UPDATE users SET notifyopts = notifyopts & ~(3::integer << (11*2)) WHERE NOT notify_comment;

ALTER TABLE users DROP COLUMN notify_announce;
ALTER TABLE users DROP COLUMN notify_dbedit;
ALTER TABLE users DROP COLUMN notify_post;
ALTER TABLE users DROP COLUMN notify_comment;

ALTER TABLE notifications ADD COLUMN prio smallint NOT NULL DEFAULT 2;

DROP FUNCTION notify(vndbid,integer,vndbid);

\i sql/func.sql
\i sql/editfunc.sql
\i sql/triggers.sql
