ALTER TABLE users ALTER COLUMN perm_lengthvote SET DEFAULT true;
CREATE        INDEX vn_length_votes_uid    ON vn_length_votes (uid);
