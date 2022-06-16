CREATE TABLE users_prefs (
  id                  vndbid NOT NULL PRIMARY KEY,
  max_sexual          smallint NOT NULL DEFAULT 0,
  max_violence        smallint NOT NULL DEFAULT 0,
  last_reports        timestamptz, -- For mods: Most recent activity seen on the reports listing
  tableopts_c         integer,
  tableopts_v         integer,
  tableopts_vt        integer, -- VN listing on tag pages
  spoilers            smallint NOT NULL DEFAULT 0,
  tags_all            boolean NOT NULL DEFAULT false,
  tags_cont           boolean NOT NULL DEFAULT true,
  tags_ero            boolean NOT NULL DEFAULT false,
  tags_tech           boolean NOT NULL DEFAULT true,
  traits_sexual       boolean NOT NULL DEFAULT false,
  skin                text NOT NULL DEFAULT '',
  customcss           text NOT NULL DEFAULT '',
  ulist_votes         jsonb,
  ulist_vnlist        jsonb,
  ulist_wish          jsonb,
  vnlang              jsonb, -- '$lang(-mtl)?' => true/false, which languages to expand/collapse on VN pages
  title_langs         jsonb,
  alttitle_langs      jsonb
);

INSERT INTO users_prefs SELECT id
    , max_sexual    
    , max_violence  
    , last_reports  
    , tableopts_c   
    , tableopts_v   
    , tableopts_vt  
    , spoilers      
    , tags_all      
    , tags_cont     
    , tags_ero      
    , tags_tech     
    , traits_sexual 
    , skin          
    , customcss     
    , ulist_votes   
    , ulist_vnlist  
    , ulist_wish    
    , vnlang        
    , title_langs   
    , alttitle_langs
  FROM users;

ALTER TABLE users_prefs              ADD CONSTRAINT users_prefs_id_fkey                FOREIGN KEY (id)        REFERENCES users         (id) ON DELETE CASCADE;

ALTER TABLE users DROP COLUMN max_sexual    ;
ALTER TABLE users DROP COLUMN max_violence  ;
ALTER TABLE users DROP COLUMN last_reports  ;
ALTER TABLE users DROP COLUMN tableopts_c   ;
ALTER TABLE users DROP COLUMN tableopts_v   ;
ALTER TABLE users DROP COLUMN tableopts_vt  ;
ALTER TABLE users DROP COLUMN spoilers      ;
ALTER TABLE users DROP COLUMN tags_all      ;
ALTER TABLE users DROP COLUMN tags_cont     ;
ALTER TABLE users DROP COLUMN tags_ero      ;
ALTER TABLE users DROP COLUMN tags_tech     ;
ALTER TABLE users DROP COLUMN traits_sexual ;
ALTER TABLE users DROP COLUMN skin          ;
ALTER TABLE users DROP COLUMN customcss     ;
ALTER TABLE users DROP COLUMN ulist_votes   ;
ALTER TABLE users DROP COLUMN ulist_vnlist  ;
ALTER TABLE users DROP COLUMN ulist_wish    ;
ALTER TABLE users DROP COLUMN vnlang        ;
ALTER TABLE users DROP COLUMN title_langs   ;
ALTER TABLE users DROP COLUMN alttitle_langs;

ALTER TABLE users_shadow ADD COLUMN ip inet NOT NULL DEFAULT '0.0.0.0';
UPDATE users_shadow SET ip = users.ip FROM users WHERE users.id = users_shadow.id;
ALTER TABLE users DROP COLUMN ip;

-- Rewrite the table to properly remove the columns.
CLUSTER users USING users_pkey;

-- users.ip is not accessible anymore, so we need a separate table to throttle
-- registrations per IP.
CREATE TABLE registration_throttle (
  ip        inet NOT NULL PRIMARY KEY,
  timeout   timestamptz NOT NULL
);

-- While I'm at it, let's remove changes.ip too. I've not used it in the past decade.
ALTER TABLE changes DROP COLUMN ip;

\i sql/func.sql
\i sql/editfunc.sql
\i sql/perms.sql
