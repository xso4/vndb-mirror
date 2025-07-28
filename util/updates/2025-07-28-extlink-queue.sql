ALTER TABLE extlinks ADD CONSTRAINT extlinks_queue CHECK((c_ref AND queue IS NOT NULL AND nextfetch IS NOT NULL) OR (queue IS NULL AND nextfetch IS NULL));
