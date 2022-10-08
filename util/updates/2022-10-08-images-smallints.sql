ALTER TABLE images
    ALTER c_votecount TYPE smallint,
    ALTER c_weight TYPE smallint,
    ALTER c_sexual_avg      TYPE smallint USING COALESCE(c_sexual_avg     *100, 200),
    ALTER c_sexual_stddev   TYPE smallint USING COALESCE(c_sexual_stddev  *100, 0),
    ALTER c_violence_avg    TYPE smallint USING COALESCE(c_violence_avg   *100, 200),
    ALTER c_violence_stddev TYPE smallint USING COALESCE(c_violence_stddev*100, 0),
    ALTER c_sexual_avg      SET DEFAULT 200,
    ALTER c_sexual_stddev   SET DEFAULT 0,
    ALTER c_violence_avg    SET DEFAULT 200,
    ALTER c_violence_stddev SET DEFAULT 0,
    ALTER c_sexual_avg      SET NOT NULL,
    ALTER c_sexual_stddev   SET NOT NULL,
    ALTER c_violence_avg    SET NOT NULL,
    ALTER c_violence_stddev SET NOT NULL;

\i sql/func.sql

SELECT update_images_cache(NULL);
