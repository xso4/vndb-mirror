package VNDB::Types;

use v5.24;
no strict 'refs';
use warnings;
use Exporter 'import';

our @EXPORT;
sub hash {
    my $name = shift;
    tie $name->%*, 'VNDB::Types::Hash', @_;
    push @EXPORT, "%$name";
}



# SQL: ENUM language
hash LANGUAGE =>
    ar => 'Arabic',
    bg => 'Bulgarian',
    ca => 'Catalan',
    cs => 'Czech',
    ck => 'Cherokee', # 'chr' in ISO 639-2 but not present in ISO 639-1, let's just use an unassigned code
    da => 'Danish',
    de => 'German',
    el => 'Greek',
    en => 'English',
    eo => 'Esperanto',
    es => 'Spanish',
    eu => 'Basque',
    fa => 'Persian',
    fi => 'Finnish',
    fr => 'French',
    ga => 'Irish',
    gd => 'Scottish Gaelic',
    he => 'Hebrew',
    hi => 'Hindi',
    hr => 'Croatian',
    hu => 'Hungarian',
    id => 'Indonesian',
    it => 'Italian',
    iu => 'Inuktitut',
    ja => 'Japanese',
    ko => 'Korean',
    mk => 'Macedonian',
    ms => 'Malay',
    la => 'Latin',
    lt => 'Lithuanian',
    lv => 'Latvian',
    nl => 'Dutch',
    no => 'Norwegian',
    pl => 'Polish',
    'pt-br' => 'Portuguese (Brazil)',
    'pt-pt' => 'Portuguese (Portugal)',
    ro => 'Romanian',
    ru => 'Russian',
    sk => 'Slovak',
    sl => 'Slovene',
    sr => 'Serbian',
    sv => 'Swedish',
    ta => 'Tagalog',
    th => 'Thai',
    tr => 'Turkish',
    uk => 'Ukrainian',
    ur => 'Urdu',
    vi => 'Vietnamese',
    zh => 'Chinese',
    'zh-Hans' => 'Chinese (simplified)',
    'zh-Hant' => 'Chinese (traditional)';



# SQL: ENUM platform
# The 'unk' platform is used to mean "Unknown" in various places (not in the DB).
hash PLATFORM =>
    win => 'Windows',
    lin => 'Linux',
    mac => 'Mac OS',
    web => 'Website',
    tdo => '3DO',
    ios => 'Apple iProduct',
    and => 'Android',
    bdp => 'Blu-ray Player',
    dos => 'DOS',
    dvd => 'DVD Player',
    drc => 'Dreamcast',
    nes => 'Famicom',
    sfc => 'Super Famicom',
    fm7 => 'FM-7',
    fm8 => 'FM-8',
    fmt => 'FM Towns',
    gba => 'Game Boy Advance',
    gbc => 'Game Boy Color',
    msx => 'MSX',
    nds => 'Nintendo DS',
    swi => 'Nintendo Switch',
    wii => 'Nintendo Wii',
    wiu => 'Nintendo Wii U',
    n3d => 'Nintendo 3DS',
    p88 => 'PC-88',
    p98 => 'PC-98',
    pce => 'PC Engine',
    pcf => 'PC-FX',
    psp => 'PlayStation Portable',
    ps1 => 'PlayStation 1',
    ps2 => 'PlayStation 2',
    ps3 => 'PlayStation 3',
    ps4 => 'PlayStation 4',
    ps5 => 'PlayStation 5',
    psv => 'PlayStation Vita',
    smd => 'Sega Mega Drive',
    scd => 'Sega Mega-CD',
    sat => 'Sega Saturn',
    vnd => 'VNDS',
    x1s => 'Sharp X1',
    x68 => 'Sharp X68000',
    xb1 => 'Xbox',
    xb3 => 'Xbox 360',
    xbo => 'Xbox One',
    xxs => 'Xbox X/S',
    mob => 'Other (mobile)',
    oth => 'Other';



# SQL: ENUM vn_relation
hash VN_RELATION =>
    seq  => { reverse => 'preq', pref => 1, txt => 'Sequel'              },
    preq => { reverse => 'seq',  pref => 0, txt => 'Prequel'             },
    set  => { reverse => 'set',  pref => 0, txt => 'Same setting'        },
    alt  => { reverse => 'alt',  pref => 0, txt => 'Alternative version' },
    char => { reverse => 'char', pref => 0, txt => 'Shares characters'   },
    side => { reverse => 'par',  pref => 1, txt => 'Side story'          },
    par  => { reverse => 'side', pref => 0, txt => 'Parent story'        },
    ser  => { reverse => 'ser',  pref => 0, txt => 'Same series'         },
    fan  => { reverse => 'orig', pref => 1, txt => 'Fandisc'             },
    orig => { reverse => 'fan',  pref => 0, txt => 'Original game'       };


hash DEVSTATUS =>
    0 => 'Finished',
    1 => 'In development',
    2 => 'Cancelled';


# SQL: ENUM producer_relation
# "Pref" relations are considered the "preferred" relation to show (as opposed to their reverse)
hash PRODUCER_RELATION =>
    old => { reverse => 'new', pref => 0, txt => 'Formerly'        },
    new => { reverse => 'old', pref => 1, txt => 'Succeeded by'    },
    spa => { reverse => 'ori', pref => 1, txt => 'Spawned'         },
    ori => { reverse => 'spa', pref => 0, txt => 'Originated from' },
    sub => { reverse => 'par', pref => 1, txt => 'Subsidiary'      },
    par => { reverse => 'sub', pref => 0, txt => 'Parent producer' },
    imp => { reverse => 'ipa', pref => 1, txt => 'Imprint'         },
    ipa => { reverse => 'imp', pref => 0, txt => 'Parent brand'    };



# SQL: ENUM producer_type
hash PRODUCER_TYPE =>
    co => 'Company',
    in => 'Individual',
    ng => 'Amateur group';



# SQL: ENUM credit_type
hash CREDIT_TYPE =>
    scenario   => 'Scenario',
    director   => 'Director',
    chardesign => 'Character design',
    art        => 'Artist',
    music      => 'Composer',
    songs      => 'Vocals',
    translator => 'Translator',
    editor     => 'Editor',
    qa         => 'Quality assurance',
    staff      => 'Staff';



hash VN_LENGTH =>
    0 => { txt => 'Unknown',    time => '',              low =>     0, high =>     0 },
    1 => { txt => 'Very short', time => '< 2 hours',     low =>     1, high =>  2*60 },
    2 => { txt => 'Short',      time => '2 - 10 hours',  low =>  2*60, high => 10*60 },
    3 => { txt => 'Medium',     time => '10 - 30 hours', low => 10*60, high => 30*60 },
    4 => { txt => 'Long',       time => '30 - 50 hours', low => 30*60, high => 50*60 },
    5 => { txt => 'Very long',  time => '> 50 hours',    low => 50*60, high => 32767 };



# SQL: ENUM anime_type
hash ANIME_TYPE => # anidb = what the UDP API returns, lowercased
    tv  => { txt => 'TV Series',    anidb => 'tv series'   },
    ova => { txt => 'OVA',          anidb => 'ova'         },
    mov => { txt => 'Movie',        anidb => 'movie'       },
    oth => { txt => 'Other',        anidb => 'other'       },
    web => { txt => 'Web',          anidb => 'web'         },
    spe => { txt => 'TV Special',   anidb => 'tv special'  },
    mv  => { txt => 'Music Video',  anidb => 'music video' };



# SQL: ENUM tag_category
hash TAG_CATEGORY =>
    cont => 'Content',
    ero  => 'Sexual content',
    tech => 'Technical';



hash ANIMATED =>
    0 => { txt => 'Unknown'                    },
    1 => { txt => 'Not animated'               },
    2 => { txt => 'Simple animations'          },
    3 => { txt => 'Some fully animated scenes' },
    4 => { txt => 'All scenes fully animated'  };



hash VOICED =>
    0 => { txt => 'Unknown'                },
    1 => { txt => 'Not voiced'             },
    2 => { txt => 'Only ero scenes voiced' },
    3 => { txt => 'Partially voiced'       },
    4 => { txt => 'Fully voiced'           };



hash AGE_RATING =>
     0 => { txt => 'All ages', ex => 'CERO A' },
     3 => { txt => '3+',       ex => '' },
     6 => { txt => '6+',       ex => '' },
     7 => { txt => '7+',       ex => '' },
     8 => { txt => '8+',       ex => '' },
     9 => { txt => '9+',       ex => '' },
    10 => { txt => '10+',      ex => '' },
    11 => { txt => '11+',      ex => '' },
    12 => { txt => '12+',      ex => 'CERO B' },
    13 => { txt => '13+',      ex => '' },
    14 => { txt => '14+',      ex => '' },
    15 => { txt => '15+',      ex => 'CERO C' },
    16 => { txt => '16+',      ex => '' },
    17 => { txt => '17+',      ex => 'CERO D' },
    18 => { txt => '18+',      ex => 'CERO Z' };



# SQL: ENUM medium
# The 'unk' medium is used in release filters to mean "unknown".
hash MEDIUM =>
    cd  => { qty => 1, txt => 'CD',                    plural => 'CDs',                    icon => 'disk'      },
    dvd => { qty => 1, txt => 'DVD',                   plural => 'DVDs',                   icon => 'disk'      },
    gdr => { qty => 1, txt => 'GD-ROM',                plural => 'GD-ROMs',                icon => 'disk'      },
    blr => { qty => 1, txt => 'Blu-ray disc',          plural => 'Blu-ray discs',          icon => 'disk'      },
    flp => { qty => 1, txt => 'Floppy',                plural => 'Floppies',               icon => 'cartridge' },
    cas => { qty => 1, txt => 'Cassette tape',         plural => 'Cassette tapes',         icon => 'cartridge' },
    mrt => { qty => 1, txt => 'Cartridge',             plural => 'Cartridges',             icon => 'cartridge' },
    mem => { qty => 1, txt => 'Memory card',           plural => 'Memory cards',           icon => 'cartridge' },
    umd => { qty => 1, txt => 'UMD',                   plural => 'UMDs',                   icon => 'disk'      },
    nod => { qty => 1, txt => 'Nintendo Optical Disc', plural => 'Nintendo Optical Discs', icon => 'disk'      },
    in  => { qty => 0, txt => 'Internet download',     plural => '',                       icon => 'download'  },
    otc => { qty => 0, txt => 'Other',                 plural => '',                       icon => 'cartridge' };



# SQL: ENUM release_type
hash RELEASE_TYPE =>
    complete => 'Complete',
    partial  => 'Partial',
    trial    => 'Trial';



# 0 = hardcoded "unknown", 2 = hardcoded 'OK'
hash RLIST_STATUS =>
    0 => 'Unknown',
    1 => 'Pending',
    2 => 'Obtained',
    3 => 'On loan',
    4 => 'Deleted';



# SQL: ENUM board_type
hash BOARD_TYPE =>
    an => { txt => 'Announcements',       post_perm => 'boardmod', index_rows =>  5, dbitem => 0 },
    db => { txt => 'VNDB discussions',    post_perm => 'board',    index_rows => 10, dbitem => 0 },
    ge => { txt => 'General discussions', post_perm => 'board',    index_rows => 10, dbitem => 0 },
    v  => { txt => 'Visual novels',       post_perm => 'board',    index_rows => 10, dbitem => 1 },
    p  => { txt => 'Producers',           post_perm => 'board',    index_rows =>  5, dbitem => 1 },
    u  => { txt => 'Users',               post_perm => 'board',    index_rows =>  5, dbitem => 1 };



# SQL: ENUM blood_type
hash BLOOD_TYPE =>
    unknown => 'Unknown',
    o       => 'O',
    a       => 'A',
    b       => 'B',
    ab      => 'AB';



# SQL: ENUM gender
hash GENDER =>
    unknown => 'Unknown or N/A',
    m       => 'Male',
    f       => 'Female',
    b       => 'Both';



# SQL: ENUM cup_size
hash CUP_SIZE =>
    ''  => 'Unknown or N/A',
    AAA => 'AAA',
    AA  => 'AA',
    map +($_,$_), 'A'..'Z';



# SQL: ENUM char_role
hash CHAR_ROLE =>
    main    => { txt => 'Protagonist',         plural => 'Protagonists'       },
    primary => { txt => 'Main character',      plural => 'Main characters'    },
    side    => { txt => 'Side character',      plural => 'Side characters'    },
    appears => { txt => 'Makes an appearance', plural => 'Make an appearance' };




# Concise implementation of an immutable hash that remembers key order.
package VNDB::Types::Hash;
use v5.24;
sub TIEHASH { shift; bless [ [ map $_[$_*2], 0..$#_/2 ], +{@_}, 0 ], __PACKAGE__ };
sub FETCH { $_[0][1]{$_[1]} }
sub EXISTS { exists $_[0][1]{$_[1]} }
sub FIRSTKEY { $_[0][2] = 0; &NEXTKEY }
sub NEXTKEY { $_[0][0][ $_[0][2]++ ] }
sub SCALAR { scalar $_[0][0]->@* }
1;
