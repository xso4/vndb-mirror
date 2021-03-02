ALTER TABLE reviews ADD COLUMN modnote    text NOT NULL DEFAULT '';

-- Not sure why NULL was allowed for the text column, let's fix that while we're here.
ALTER TABLE reviews ALTER COLUMN text SET NOT NULL;
