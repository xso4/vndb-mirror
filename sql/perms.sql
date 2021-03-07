-- vndb_site

DROP OWNED BY vndb_site;
GRANT CONNECT, TEMP ON DATABASE :DBNAME TO vndb_site;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO vndb_site;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vndb_site;

GRANT SELECT, INSERT                 ON anime                    TO vndb_site;
GRANT         INSERT                 ON audit_log                TO vndb_site;
GRANT SELECT, INSERT                 ON changes                  TO vndb_site;
GRANT SELECT, INSERT, UPDATE         ON chars                    TO vndb_site;
GRANT SELECT, INSERT                 ON chars_hist               TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON chars_traits             TO vndb_site;
GRANT SELECT, INSERT                 ON chars_traits_hist        TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON chars_vns                TO vndb_site;
GRANT SELECT, INSERT                 ON chars_vns_hist           TO vndb_site;
GRANT SELECT, INSERT, UPDATE         ON docs                     TO vndb_site;
GRANT SELECT, INSERT                 ON docs_hist                TO vndb_site;
GRANT SELECT, INSERT, UPDATE         ON images                   TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON image_votes              TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON login_throttle           TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON notification_subs        TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON notifications            TO vndb_site;
GRANT SELECT, INSERT, UPDATE         ON producers                TO vndb_site;
GRANT SELECT, INSERT                 ON producers_hist           TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON producers_relations      TO vndb_site;
GRANT SELECT, INSERT                 ON producers_relations_hist TO vndb_site;
GRANT SELECT                         ON quotes                   TO vndb_site;
GRANT SELECT, INSERT, UPDATE         ON releases                 TO vndb_site;
GRANT SELECT, INSERT                 ON releases_hist            TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON releases_lang            TO vndb_site;
GRANT SELECT, INSERT                 ON releases_lang_hist       TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON releases_media           TO vndb_site;
GRANT SELECT, INSERT                 ON releases_media_hist      TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON releases_platforms       TO vndb_site;
GRANT SELECT, INSERT                 ON releases_platforms_hist  TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON releases_producers       TO vndb_site;
GRANT SELECT, INSERT                 ON releases_producers_hist  TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON releases_vn              TO vndb_site;
GRANT SELECT, INSERT                 ON releases_vn_hist         TO vndb_site;
GRANT SELECT, INSERT, UPDATE         ON reports                  TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON reviews                  TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON reviews_posts            TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON reviews_votes            TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON rlists                   TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON saved_queries            TO vndb_site;
-- No access to the 'sessions' table, managed by the user_* functions.
GRANT SELECT                         ON shop_denpa               TO vndb_site;
GRANT SELECT                         ON shop_dlsite              TO vndb_site;
GRANT SELECT                         ON shop_jlist               TO vndb_site;
GRANT SELECT                         ON shop_mg                  TO vndb_site;
GRANT SELECT                         ON shop_playasia            TO vndb_site;
GRANT SELECT, INSERT, UPDATE         ON staff                    TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON staff_alias              TO vndb_site;
GRANT SELECT, INSERT                 ON staff_alias_hist         TO vndb_site;
GRANT SELECT, INSERT                 ON staff_hist               TO vndb_site;
GRANT SELECT, UPDATE                 ON stats_cache              TO vndb_site;
GRANT SELECT, INSERT, UPDATE         ON tags                     TO vndb_site;
GRANT SELECT, INSERT                 ON tags_hist                TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON tags_parents             TO vndb_site;
GRANT SELECT, INSERT                 ON tags_parents_hist        TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON tags_vn                  TO vndb_site;
GRANT SELECT                         ON tags_vn_inherit          TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON threads                  TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON threads_boards           TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON threads_poll_options     TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON threads_poll_votes       TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON threads_posts            TO vndb_site;
GRANT         INSERT                 ON trace_log                TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON traits                   TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON traits_chars             TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON traits_parents           TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON ulist_labels             TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON ulist_vns                TO vndb_site;
GRANT SELECT, INSERT, UPDATE, DELETE ON ulist_vns_labels         TO vndb_site;

-- users table is special; The 'perm_usermod', 'passwd' and 'mail' columns are
-- protected and can only be accessed through the user_* functions.
GRANT SELECT ( id, username, registered, ip, ign_votes, email_confirmed, last_reports
             , perm_board, perm_boardmod, perm_dbmod, perm_edit, perm_imgvote, perm_tag, perm_tagmod, perm_usermod, perm_imgmod, perm_review
             , skin, customcss, notify_dbedit, notify_announce, notify_post, notify_comment
             , tags_all, tags_cont, tags_ero, tags_tech, spoilers, traits_sexual, max_sexual, max_violence
             , nodistract_can, nodistract_noads, nodistract_nofancy, support_can, support_enabled, uniname_can, uniname, pubskin_can, pubskin_enabled
             , ulist_votes, ulist_vnlist, ulist_wish, tableopts_c
             , c_vns, c_wish, c_votes, c_changes, c_imgvotes, c_tags),
      INSERT ( username, mail, ip),
      UPDATE ( username, ign_votes, email_confirmed, last_reports
             , perm_board, perm_boardmod, perm_dbmod, perm_edit, perm_imgvote, perm_tag, perm_tagmod, perm_imgmod, perm_review
             , skin, customcss, notify_dbedit, notify_announce, notify_post, notify_comment
             , tags_all, tags_cont, tags_ero, tags_tech, spoilers, traits_sexual, max_sexual, max_violence
             , nodistract_can, nodistract_noads, nodistract_nofancy, support_can, support_enabled, uniname_can, uniname, pubskin_can, pubskin_enabled
             , ulist_votes, ulist_vnlist, ulist_wish, tableopts_c
             , c_vns, c_wish, c_votes, c_changes, c_imgvotes, c_tags) ON users TO vndb_site;

GRANT SELECT, INSERT, UPDATE         ON vn                       TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON vn_anime                 TO vndb_site;
GRANT SELECT, INSERT                 ON vn_anime_hist            TO vndb_site;
GRANT SELECT, INSERT                 ON vn_hist                  TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON vn_relations             TO vndb_site;
GRANT SELECT, INSERT                 ON vn_relations_hist        TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON vn_screenshots           TO vndb_site;
GRANT SELECT, INSERT                 ON vn_screenshots_hist      TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON vn_seiyuu                TO vndb_site;
GRANT SELECT, INSERT                 ON vn_seiyuu_hist           TO vndb_site;
GRANT SELECT, INSERT,         DELETE ON vn_staff                 TO vndb_site;
GRANT SELECT, INSERT                 ON vn_staff_hist            TO vndb_site;
GRANT SELECT, INSERT                 ON wikidata                 TO vndb_site;




-- vndb_multi
-- (Assuming all modules are loaded)

DROP OWNED BY vndb_multi;
GRANT CONNECT, TEMP ON DATABASE :DBNAME TO vndb_multi;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO vndb_multi;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vndb_multi;

GRANT SELECT, INSERT, UPDATE         ON anime                    TO vndb_multi;
GRANT SELECT                         ON changes                  TO vndb_multi;
GRANT SELECT                         ON chars                    TO vndb_multi;
GRANT SELECT                         ON chars_hist               TO vndb_multi;
GRANT SELECT                         ON chars_traits             TO vndb_multi;
GRANT SELECT                         ON chars_vns                TO vndb_multi;
GRANT SELECT                         ON docs                     TO vndb_multi;
GRANT SELECT                         ON docs_hist                TO vndb_multi;
GRANT SELECT,         UPDATE         ON images                   TO vndb_multi;
GRANT SELECT                         ON image_votes              TO vndb_multi;
GRANT SELECT, INSERT, UPDATE, DELETE ON login_throttle           TO vndb_multi;
GRANT SELECT, INSERT, UPDATE, DELETE ON notifications            TO vndb_multi;
GRANT SELECT,         UPDATE         ON producers                TO vndb_multi;
GRANT SELECT                         ON producers_hist           TO vndb_multi;
GRANT SELECT                         ON producers_relations      TO vndb_multi;
GRANT SELECT                         ON quotes                   TO vndb_multi;
GRANT SELECT                         ON releases                 TO vndb_multi;
GRANT SELECT                         ON releases_hist            TO vndb_multi;
GRANT SELECT                         ON releases_lang            TO vndb_multi;
GRANT SELECT                         ON releases_media           TO vndb_multi;
GRANT SELECT                         ON releases_platforms       TO vndb_multi;
GRANT SELECT                         ON releases_producers       TO vndb_multi;
GRANT SELECT                         ON releases_vn              TO vndb_multi;
GRANT SELECT,         UPDATE         ON reviews                  TO vndb_multi;
GRANT SELECT                         ON reviews_posts            TO vndb_multi;
GRANT SELECT                         ON reviews_votes            TO vndb_multi;
GRANT SELECT, INSERT, UPDATE, DELETE ON rlists                   TO vndb_multi;
GRANT SELECT (expires)               ON sessions                 TO vndb_multi;
GRANT                         DELETE ON sessions                 TO vndb_multi;
GRANT SELECT, INSERT, UPDATE, DELETE ON shop_denpa               TO vndb_multi;
GRANT SELECT, INSERT, UPDATE, DELETE ON shop_dlsite              TO vndb_multi;
GRANT SELECT, INSERT, UPDATE, DELETE ON shop_jlist               TO vndb_multi;
GRANT SELECT, INSERT, UPDATE, DELETE ON shop_mg                  TO vndb_multi;
GRANT SELECT, INSERT, UPDATE, DELETE ON shop_playasia            TO vndb_multi;
GRANT SELECT, INSERT, UPDATE, DELETE ON shop_playasia_gtin       TO vndb_multi;
GRANT SELECT                         ON staff                    TO vndb_multi;
GRANT SELECT                         ON staff_alias              TO vndb_multi;
GRANT SELECT                         ON staff_alias_hist         TO vndb_multi;
GRANT SELECT                         ON staff_hist               TO vndb_multi;
GRANT SELECT,         UPDATE         ON stats_cache              TO vndb_multi;
GRANT SELECT                         ON tags                     TO vndb_multi;
GRANT SELECT                         ON tags_hist                TO vndb_multi;
GRANT SELECT                         ON tags_parents             TO vndb_multi;
GRANT SELECT                         ON tags_parents_hist        TO vndb_multi;
GRANT SELECT                         ON tags_vn                  TO vndb_multi;
GRANT SELECT                         ON tags_vn_inherit          TO vndb_multi; -- tag_vn_calc() is SECURITY DEFINER due to index drop/create, so no extra perms needed here
GRANT SELECT                         ON threads                  TO vndb_multi;
GRANT SELECT                         ON threads_boards           TO vndb_multi;
GRANT SELECT                         ON threads_posts            TO vndb_multi;
GRANT SELECT,         UPDATE         ON traits                   TO vndb_multi;
GRANT SELECT                         ON traits_chars             TO vndb_multi; -- traits_chars_calc() is SECURITY DEFINER
GRANT SELECT                         ON traits_parents           TO vndb_multi;
GRANT SELECT, INSERT, UPDATE, DELETE ON ulist_labels             TO vndb_multi;
GRANT SELECT, INSERT, UPDATE, DELETE ON ulist_vns                TO vndb_multi;
GRANT SELECT, INSERT, UPDATE, DELETE ON ulist_vns_labels         TO vndb_multi;

GRANT SELECT (id, username, registered, ign_votes, email_confirmed, notify_dbedit, notify_announce, notify_post, notify_comment, c_vns, c_wish, c_votes, c_changes, c_imgvotes, c_tags, perm_imgvote, perm_imgmod),
      UPDATE (                                                                                                                   c_vns, c_wish, c_votes, c_changes, c_imgvotes, c_tags                           ) ON users TO vndb_multi;
GRANT                         DELETE ON users                    TO vndb_multi;

GRANT SELECT,         UPDATE         ON vn                       TO vndb_multi;
GRANT SELECT                         ON vn_anime                 TO vndb_multi;
GRANT SELECT                         ON vn_hist                  TO vndb_multi;
GRANT SELECT                         ON vn_relations             TO vndb_multi;
GRANT SELECT                         ON vn_screenshots           TO vndb_multi;
GRANT SELECT                         ON vn_screenshots_hist      TO vndb_multi;
GRANT SELECT                         ON vn_seiyuu                TO vndb_multi;
GRANT SELECT                         ON vn_staff                 TO vndb_multi;
GRANT SELECT                         ON vn_staff_hist            TO vndb_multi;
GRANT SELECT, INSERT, UPDATE         ON wikidata                 TO vndb_multi;
