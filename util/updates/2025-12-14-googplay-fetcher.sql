update extlinks set nextfetch = now(), queue = 'el-triage' where c_ref and site = 'googplay';
