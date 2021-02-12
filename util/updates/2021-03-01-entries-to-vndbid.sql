-- Public dump breakage:
--   SELECT .. FROM vn WHERE id = 10;
--   SELECT .. FROM vn WHERE id IN(1,2,3);
--   SELECT 'https://vndb.org/v'||id FROM vn;

BEGIN;

ALTER TABLE changes                  DROP CONSTRAINT changes_requester_fkey;
ALTER TABLE chars                    DROP CONSTRAINT chars_main_fkey;
ALTER TABLE chars_hist               DROP CONSTRAINT chars_hist_main_fkey;
ALTER TABLE chars_traits             DROP CONSTRAINT chars_traits_id_fkey;
ALTER TABLE chars_vns                DROP CONSTRAINT chars_vns_id_fkey;
ALTER TABLE chars_vns                DROP CONSTRAINT chars_vns_rid_fkey;
ALTER TABLE chars_vns                DROP CONSTRAINT chars_vns_vid_fkey;
ALTER TABLE chars_vns_hist           DROP CONSTRAINT chars_vns_hist_rid_fkey;
ALTER TABLE chars_vns_hist           DROP CONSTRAINT chars_vns_hist_vid_fkey;
ALTER TABLE image_votes              DROP CONSTRAINT image_votes_uid_fkey;
ALTER TABLE notification_subs        DROP CONSTRAINT notification_subs_uid_fkey;
ALTER TABLE notifications            DROP CONSTRAINT notifications_uid_fkey;
ALTER TABLE producers_relations      DROP CONSTRAINT producers_relations_pid_fkey;
ALTER TABLE producers_relations_hist DROP CONSTRAINT producers_relations_hist_pid_fkey;
ALTER TABLE quotes                   DROP CONSTRAINT quotes_vid_fkey;
ALTER TABLE releases_lang            DROP CONSTRAINT releases_lang_id_fkey;
ALTER TABLE releases_media           DROP CONSTRAINT releases_media_id_fkey;
ALTER TABLE releases_platforms       DROP CONSTRAINT releases_platforms_id_fkey;
ALTER TABLE releases_producers       DROP CONSTRAINT releases_producers_id_fkey;
ALTER TABLE releases_producers       DROP CONSTRAINT releases_producers_pid_fkey;
ALTER TABLE releases_producers_hist  DROP CONSTRAINT releases_producers_hist_pid_fkey;
ALTER TABLE releases_vn              DROP CONSTRAINT releases_vn_id_fkey;
ALTER TABLE releases_vn              DROP CONSTRAINT releases_vn_vid_fkey;
ALTER TABLE releases_vn_hist         DROP CONSTRAINT releases_vn_hist_vid_fkey;
ALTER TABLE reviews                  DROP CONSTRAINT reviews_rid_fkey;
ALTER TABLE reviews                  DROP CONSTRAINT reviews_uid_fkey;
ALTER TABLE reviews                  DROP CONSTRAINT reviews_vid_fkey;
ALTER TABLE reviews_posts            DROP CONSTRAINT reviews_posts_uid_fkey;
ALTER TABLE reviews_votes            DROP CONSTRAINT reviews_votes_uid_fkey;
ALTER TABLE rlists                   DROP CONSTRAINT rlists_rid_fkey;
ALTER TABLE rlists                   DROP CONSTRAINT rlists_uid_fkey;
ALTER TABLE saved_queries            DROP CONSTRAINT saved_queries_uid_fkey;
ALTER TABLE sessions                 DROP CONSTRAINT sessions_uid_fkey;
ALTER TABLE staff_alias              DROP CONSTRAINT staff_alias_id_fkey;
ALTER TABLE tags                     DROP CONSTRAINT tags_addedby_fkey;
ALTER TABLE tags_vn                  DROP CONSTRAINT tags_vn_uid_fkey;
ALTER TABLE tags_vn                  DROP CONSTRAINT tags_vn_vid_fkey;
ALTER TABLE threads_poll_votes       DROP CONSTRAINT threads_poll_votes_uid_fkey;
ALTER TABLE threads_posts            DROP CONSTRAINT threads_posts_uid_fkey;
ALTER TABLE traits                   DROP CONSTRAINT traits_addedby_fkey;
ALTER TABLE ulist_labels             DROP CONSTRAINT ulist_labels_uid_fkey;
ALTER TABLE ulist_vns                DROP CONSTRAINT ulist_vns_uid_fkey;
ALTER TABLE ulist_vns                DROP CONSTRAINT ulist_vns_vid_fkey;
ALTER TABLE ulist_vns_labels         DROP CONSTRAINT ulist_vns_labels_uid_fkey;
ALTER TABLE ulist_vns_labels         DROP CONSTRAINT ulist_vns_labels_uid_lbl_fkey;
ALTER TABLE ulist_vns_labels         DROP CONSTRAINT ulist_vns_labels_uid_vid_fkey;
ALTER TABLE ulist_vns_labels         DROP CONSTRAINT ulist_vns_labels_vid_fkey;
ALTER TABLE vn_anime                 DROP CONSTRAINT vn_anime_id_fkey;
ALTER TABLE vn_relations             DROP CONSTRAINT vn_relations_id_fkey;
ALTER TABLE vn_relations             DROP CONSTRAINT vn_relations_vid_fkey;
ALTER TABLE vn_relations_hist        DROP CONSTRAINT vn_relations_vid_fkey;
ALTER TABLE vn_screenshots           DROP CONSTRAINT vn_screenshots_id_fkey;
ALTER TABLE vn_screenshots           DROP CONSTRAINT vn_screenshots_rid_fkey;
ALTER TABLE vn_screenshots_hist      DROP CONSTRAINT vn_screenshots_hist_rid_fkey;
ALTER TABLE vn_seiyuu                DROP CONSTRAINT vn_seiyuu_cid_fkey;
ALTER TABLE vn_seiyuu                DROP CONSTRAINT vn_seiyuu_id_fkey;
ALTER TABLE vn_seiyuu_hist           DROP CONSTRAINT vn_seiyuu_hist_cid_fkey;
ALTER TABLE vn_staff                 DROP CONSTRAINT vn_staff_id_fkey;

DROP INDEX chars_vns_pkey;
DROP INDEX chars_vns_hist_pkey;

ALTER TABLE rlists ALTER COLUMN uid DROP DEFAULT;
ALTER TABLE rlists ALTER COLUMN rid DROP DEFAULT;


DROP INDEX changes_itemrev;
ALTER TABLE changes ALTER COLUMN itemid TYPE vndbid USING vndbid(type::text, itemid);
ALTER TABLE changes DROP COLUMN type;

ALTER TABLE threads_boards DROP CONSTRAINT threads_boards_pkey;
ALTER TABLE threads_boards ALTER COLUMN iid DROP DEFAULT;
ALTER TABLE threads_boards ALTER COLUMN iid DROP NOT NULL;
ALTER TABLE threads_boards ALTER COLUMN iid TYPE vndbid USING CASE WHEN iid = 0 THEN NULL ELSE vndbid(type::text, iid) END;

ALTER TABLE audit_log ALTER COLUMN by_uid TYPE vndbid USING vndbid('u', by_uid);
ALTER TABLE audit_log ALTER COLUMN affected_uid TYPE vndbid USING vndbid('u', affected_uid);
ALTER TABLE reports ALTER COLUMN uid TYPE vndbid USING vndbid('u', uid);


ALTER TABLE chars ALTER COLUMN id DROP DEFAULT;
ALTER TABLE chars ALTER COLUMN id TYPE vndbid USING vndbid('c', id);
ALTER TABLE chars ALTER COLUMN id SET DEFAULT vndbid('c', nextval('chars_id_seq')::int);
ALTER TABLE chars ADD CONSTRAINT chars_id_check CHECK(vndbid_type(id) = 'c');

ALTER TABLE chars        ALTER COLUMN main TYPE vndbid USING vndbid('c', main);
ALTER TABLE chars_hist   ALTER COLUMN main TYPE vndbid USING vndbid('c', main);
ALTER TABLE chars_traits ALTER COLUMN id TYPE vndbid USING vndbid('c', id);
ALTER TABLE chars_vns    ALTER COLUMN id TYPE vndbid USING vndbid('c', id);
ALTER TABLE traits_chars   ALTER COLUMN cid TYPE vndbid USING vndbid('c', cid);
ALTER TABLE vn_seiyuu      ALTER COLUMN cid TYPE vndbid USING vndbid('c', cid);
ALTER TABLE vn_seiyuu_hist ALTER COLUMN cid TYPE vndbid USING vndbid('c', cid);


ALTER TABLE docs ALTER COLUMN id DROP DEFAULT;
ALTER TABLE docs ALTER COLUMN id TYPE vndbid USING vndbid('d', id);
ALTER TABLE docs ALTER COLUMN id SET DEFAULT vndbid('d', nextval('docs_id_seq')::int);
ALTER TABLE docs ADD CONSTRAINT docs_id_check CHECK(vndbid_type(id) = 'd');


ALTER TABLE producers ALTER COLUMN id DROP DEFAULT;
ALTER TABLE producers ALTER COLUMN id TYPE vndbid USING vndbid('p', id);
ALTER TABLE producers ALTER COLUMN id SET DEFAULT vndbid('p', nextval('producers_id_seq')::int);
ALTER TABLE producers ADD CONSTRAINT producers_id_check CHECK(vndbid_type(id) = 'p');

ALTER TABLE producers_relations      ALTER COLUMN id  TYPE vndbid USING vndbid('p', id);
ALTER TABLE producers_relations      ALTER COLUMN pid TYPE vndbid USING vndbid('p', pid);
ALTER TABLE producers_relations_hist ALTER COLUMN pid TYPE vndbid USING vndbid('p', pid);
ALTER TABLE releases_producers       ALTER COLUMN pid TYPE vndbid USING vndbid('p', pid);
ALTER TABLE releases_producers_hist  ALTER COLUMN pid TYPE vndbid USING vndbid('p', pid);


ALTER TABLE releases ALTER COLUMN id DROP DEFAULT;
ALTER TABLE releases ALTER COLUMN id TYPE vndbid USING vndbid('r', id);
ALTER TABLE releases ALTER COLUMN id SET DEFAULT vndbid('r', nextval('releases_id_seq')::int);
ALTER TABLE releases ADD CONSTRAINT releases_id_check CHECK(vndbid_type(id) = 'r');

ALTER TABLE chars_vns                ALTER COLUMN rid TYPE vndbid USING vndbid('r', rid);
ALTER TABLE chars_vns_hist           ALTER COLUMN rid TYPE vndbid USING vndbid('r', rid);
ALTER TABLE releases_lang            ALTER COLUMN id  TYPE vndbid USING vndbid('r', id);
ALTER TABLE releases_media           ALTER COLUMN id  TYPE vndbid USING vndbid('r', id);
ALTER TABLE releases_platforms       ALTER COLUMN id  TYPE vndbid USING vndbid('r', id);
ALTER TABLE releases_producers       ALTER COLUMN id  TYPE vndbid USING vndbid('r', id);
ALTER TABLE releases_vn              ALTER COLUMN id  TYPE vndbid USING vndbid('r', id);
ALTER TABLE reviews                  ALTER COLUMN rid TYPE vndbid USING vndbid('r', rid);
ALTER TABLE rlists                   ALTER COLUMN rid TYPE vndbid USING vndbid('r', rid);
ALTER TABLE vn_screenshots           ALTER COLUMN rid TYPE vndbid USING vndbid('r', rid);
ALTER TABLE vn_screenshots_hist      ALTER COLUMN rid TYPE vndbid USING vndbid('r', rid);


ALTER TABLE staff ALTER COLUMN id DROP DEFAULT;
ALTER TABLE staff ALTER COLUMN id TYPE vndbid USING vndbid('s', id);
ALTER TABLE staff ALTER COLUMN id SET DEFAULT vndbid('s', nextval('staff_id_seq')::int);
ALTER TABLE staff ADD CONSTRAINT staff_id_check CHECK(vndbid_type(id) = 's');

ALTER TABLE staff_alias ALTER COLUMN id TYPE vndbid USING vndbid('s', id);


ALTER TABLE vn ALTER COLUMN id DROP DEFAULT;
ALTER TABLE vn ALTER COLUMN id TYPE vndbid USING vndbid('v', id);
ALTER TABLE vn ALTER COLUMN id SET DEFAULT vndbid('v', nextval('vn_id_seq')::int);
ALTER TABLE vn ADD CONSTRAINT vn_id_check CHECK(vndbid_type(id) = 'v');

ALTER TABLE chars_vns          ALTER COLUMN vid TYPE vndbid USING vndbid('v', vid);
ALTER TABLE chars_vns_hist     ALTER COLUMN vid TYPE vndbid USING vndbid('v', vid);
ALTER TABLE quotes             ALTER COLUMN vid TYPE vndbid USING vndbid('v', vid);
ALTER TABLE releases_vn        ALTER COLUMN vid TYPE vndbid USING vndbid('v', vid);
ALTER TABLE releases_vn_hist   ALTER COLUMN vid TYPE vndbid USING vndbid('v', vid);
ALTER TABLE reviews            ALTER COLUMN vid TYPE vndbid USING vndbid('v', vid);
ALTER TABLE tags_vn            ALTER COLUMN vid TYPE vndbid USING vndbid('v', vid);
ALTER TABLE tags_vn_inherit    ALTER COLUMN vid TYPE vndbid USING vndbid('v', vid);
ALTER TABLE ulist_vns          ALTER COLUMN vid TYPE vndbid USING vndbid('v', vid);
ALTER TABLE ulist_vns_labels   ALTER COLUMN vid TYPE vndbid USING vndbid('v', vid);
ALTER TABLE vn_anime           ALTER COLUMN id  TYPE vndbid USING vndbid('v', id);
ALTER TABLE vn_relations       ALTER COLUMN id  TYPE vndbid USING vndbid('v', id);
ALTER TABLE vn_relations       ALTER COLUMN vid TYPE vndbid USING vndbid('v', vid);
ALTER TABLE vn_relations_hist  ALTER COLUMN vid TYPE vndbid USING vndbid('v', vid);
ALTER TABLE vn_screenshots     ALTER COLUMN id  TYPE vndbid USING vndbid('v', id);
ALTER TABLE vn_seiyuu          ALTER COLUMN id  TYPE vndbid USING vndbid('v', id);
ALTER TABLE vn_staff           ALTER COLUMN id  TYPE vndbid USING vndbid('v', id);


ALTER TABLE users ALTER COLUMN id DROP DEFAULT;
ALTER TABLE users ALTER COLUMN id TYPE vndbid USING vndbid('u', id);
ALTER TABLE users ALTER COLUMN id SET DEFAULT vndbid('u', nextval('users_id_seq')::int);
ALTER TABLE users ADD CONSTRAINT users_id_check CHECK(vndbid_type(id) = 'u');

ALTER TABLE changes                  ALTER COLUMN requester TYPE vndbid USING vndbid('u', requester);
ALTER TABLE image_votes              ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);
ALTER TABLE notification_subs        ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);
ALTER TABLE notifications            ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);
ALTER TABLE reviews                  ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);
ALTER TABLE reviews_posts            ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);
ALTER TABLE reviews_votes            ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);
ALTER TABLE rlists                   ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);
ALTER TABLE saved_queries            ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);
ALTER TABLE sessions                 ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);
ALTER TABLE tags                     ALTER COLUMN addedby   TYPE vndbid USING vndbid('u', addedby);
ALTER TABLE tags_vn                  ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);
ALTER TABLE threads_poll_votes       ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);
ALTER TABLE threads_posts            ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);
ALTER TABLE traits                   ALTER COLUMN addedby   TYPE vndbid USING vndbid('u', addedby);
ALTER TABLE ulist_labels             ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);
ALTER TABLE ulist_vns                ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);
ALTER TABLE ulist_vns_labels         ALTER COLUMN uid       TYPE vndbid USING vndbid('u', uid);

ALTER TABLE images ALTER COLUMN c_uids DROP DEFAULT;
ALTER TABLE images ALTER COLUMN c_uids TYPE vndbid[] USING '{}';
ALTER TABLE images ALTER COLUMN c_uids SET DEFAULT '{}';

DROP FUNCTION edit_revtable(dbentry_type, integer, integer);
DROP FUNCTION edit_commit();
DROP FUNCTION edit_committed(dbentry_type, edit_rettype);
DROP FUNCTION edit_c_init(integer, integer);
DROP FUNCTION edit_d_init(integer, integer);
DROP FUNCTION edit_p_init(integer, integer);
DROP FUNCTION edit_r_init(integer, integer);
DROP FUNCTION edit_s_init(integer, integer);
DROP FUNCTION edit_v_init(integer, integer);
DROP FUNCTION edit_c_commit();
DROP FUNCTION edit_d_commit();
DROP FUNCTION edit_p_commit();
DROP FUNCTION edit_r_commit();
DROP FUNCTION edit_s_commit();
DROP FUNCTION edit_v_commit();

DROP FUNCTION update_vncache(integer);
DROP FUNCTION tag_vn_calc(integer);
DROP FUNCTION traits_chars_calc(integer);
DROP FUNCTION ulist_labels_create(integer);
DROP FUNCTION item_info(id vndbid, num int);
DROP FUNCTION notify(iid vndbid, num integer, uid integer);
DROP FUNCTION update_users_ulist_stats(integer);
DROP FUNCTION user_getscryptargs(integer);
DROP FUNCTION user_login(integer, bytea, bytea);
DROP FUNCTION user_logout(integer, bytea);
DROP FUNCTION user_isvalidsession(integer, bytea, session_type);
DROP FUNCTION user_emailtoid(text);
DROP FUNCTION user_resetpass(text, bytea);
DROP FUNCTION user_setpass(integer, bytea, bytea);
DROP FUNCTION user_isauth(integer, integer, bytea);
DROP FUNCTION user_getmail(integer, integer, bytea);
DROP FUNCTION user_setmail_token(integer, bytea, bytea, text);
DROP FUNCTION user_setmail_confirm(integer, bytea);
DROP FUNCTION user_setperm_usermod(integer, integer, bytea, boolean);
DROP FUNCTION user_admin_setpass(integer, integer, bytea, bytea);
DROP FUNCTION user_admin_setmail(integer, integer, bytea, text);
\i sql/func.sql
\i sql/editfunc.sql
DROP TYPE edit_rettype;

COMMIT;

-- Need to do this analyze to ensure adding the foreign key constraints will use proper query plans.
ANALYZE;
\i sql/tableattrs.sql
\i sql/perms.sql
SELECT update_images_cache(NULL);
