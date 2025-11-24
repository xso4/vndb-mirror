ALTER TABLE users_prefs
  ADD COLUMN c_noti_low  smallint,
  ADD COLUMN c_noti_mid  smallint,
  ADD COLUMN c_noti_high smallint;

\i sql/triggers.sql
