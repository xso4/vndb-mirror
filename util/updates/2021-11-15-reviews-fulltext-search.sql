CREATE        INDEX reviews_ts             ON reviews USING gin(bb_tsvector(text));
CREATE        INDEX reviews_posts_ts       ON reviews_posts USING gin(bb_tsvector(msg));
