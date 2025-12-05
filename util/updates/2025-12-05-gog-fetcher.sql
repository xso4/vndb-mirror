update extlinks set nextfetch = now(), queue = 'el/gog' where c_ref and site = 'gog';
