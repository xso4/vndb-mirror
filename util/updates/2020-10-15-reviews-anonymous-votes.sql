ALTER TABLE reviews_votes ADD COLUMN ip      inet;
CREATE UNIQUE INDEX reviews_votes_id_ip    ON reviews_votes (id,ip);
\i sql/func.sql
SELECT update_reviews_votes_cache(id) FROM reviews;
