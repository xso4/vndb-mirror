ALTER TYPE notification_ntype ADD VALUE 'subapply' AFTER 'subreview';
ALTER TABLE notification_subs ADD COLUMN subapply    boolean NOT NULL DEFAULT false;
\i sql/func.sql
