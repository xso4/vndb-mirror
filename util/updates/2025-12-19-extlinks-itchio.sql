UPDATE extlinks
   SET value = regexp_replace(value, '\.itch\.io/', '/')
     , queue = CASE WHEN c_ref THEN 'el-triage' ELSE NULL END
     , nextfetch = CASE WHEN c_ref THEN NOW() ELSE NULL END
 WHERE site = 'itch';
