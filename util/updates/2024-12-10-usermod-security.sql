DROP FUNCTION user_setperm_usermod(vndbid, vndbid, bytea, boolean);
-- was accidentally kept in func.sql, despite being dropped back in 8e057e5b177259998299b62ff56037949eba1623
DROP FUNCTION user_admin_setpass(vndbid, vndbid, bytea, bytea);

\i sql/func.sql
