UPDATE releases      SET minage = NULL WHERE minage = -1;
UPDATE releases_hist SET minage = NULL WHERE minage = -1;
