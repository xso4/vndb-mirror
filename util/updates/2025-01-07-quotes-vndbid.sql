BEGIN;
ALTER TABLE quotes_log   DROP CONSTRAINT quotes_log_id_fkey;
ALTER TABLE quotes_votes DROP CONSTRAINT quotes_votes_id_fkey;

ALTER TABLE quotes
    ALTER COLUMN id DROP DEFAULT,
    ALTER COLUMN id TYPE vndbid(q) USING vndbid('q', id),
    ALTER COLUMN id SET DEFAULT vndbid('q', nextval('quotes_id_seq'));

ALTER TABLE quotes_log   ALTER COLUMN id TYPE vndbid(q) USING vndbid('q', id);
ALTER TABLE quotes_votes ALTER COLUMN id TYPE vndbid(q) USING vndbid('q', id);

ALTER TABLE quotes_log               ADD CONSTRAINT quotes_log_id_fkey                 FOREIGN KEY (id)        REFERENCES quotes        (id) ON DELETE CASCADE;
ALTER TABLE quotes_votes             ADD CONSTRAINT quotes_votes_id_fkey               FOREIGN KEY (id)        REFERENCES quotes        (id) ON DELETE CASCADE;
COMMIT;
