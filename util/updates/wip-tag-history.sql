-- 'deleted' state is now represented as (hidden && locked)
-- (hidden && !locked) now means 'awaiting moderation'
UPDATE vn        SET locked = true WHERE hidden AND NOT locked;
UPDATE producers SET locked = true WHERE hidden AND NOT locked;
UPDATE staff     SET locked = true WHERE hidden AND NOT locked;
UPDATE chars     SET locked = true WHERE hidden AND NOT locked;
UPDATE releases  SET locked = true WHERE hidden AND NOT locked;
UPDATE docs      SET locked = true WHERE hidden AND NOT locked;
UPDATE changes   SET ilock  = true WHERE ihid   AND NOT ilock;
