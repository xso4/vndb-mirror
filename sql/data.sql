INSERT INTO global_settings (id) VALUES (TRUE);

INSERT INTO users (id, username, notifyopts) VALUES ('u1', 'multi', 0);
SELECT setval('users_id_seq', 2);

INSERT INTO stats_cache (section, count) VALUES
  ('vn',            0),
  ('producers',     0),
  ('releases',      0),
  ('chars',         0),
  ('staff',         0),
  ('tags',          0),
  ('traits',        0);
