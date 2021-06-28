CREATE TABLE global_settings (
  -- Only permit a single row in this table
  id                    boolean NOT NULL PRIMARY KEY DEFAULT FALSE CONSTRAINT global_settings_single_row CHECK(id),
  -- locks down any DB edits, including image voting and tagging
  lockdown_edit         boolean NOT NULL DEFAULT FALSE,
  -- locks down any forum & review posting
  lockdown_board        boolean NOT NULL DEFAULT FALSE,
  lockdown_registration boolean NOT NULL DEFAULT FALSE
);

INSERT INTO global_settings (id) VALUES (TRUE);

\i sql/perms.sql
