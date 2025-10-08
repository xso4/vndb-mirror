package VNDB::Types;

use v5.36;
use Exporter 'import';

our @EXPORT;
sub hash {
    my $name = shift;
    push @EXPORT, "%$name";
    no strict 'refs';
    tie $name->%*, 'VNDB::Types::Hash', @_;
}



# SQL: ENUM language
# 'latin' indicates whether the language is primarily written in a latin-ish script.
# 'rank' is for quick selection of commonly used languages.
hash LANGUAGE =>
    ar       => { latin => 0, rank => 0, txt => 'Arabic' },
    eu       => { latin => 1, rank => 0, txt => 'Basque' },
    be       => { latin => 0, rank => 0, txt => 'Belarusian' },
    bg       => { latin => 1, rank => 0, txt => 'Bulgarian' },
    bs       => { latin => 0, rank => 0, txt => 'Bosnian' },
    ca       => { latin => 1, rank => 0, txt => 'Catalan' },
    ck       => { latin => 0, rank => 0, txt => 'Cherokee' }, # 'chr' in ISO 639-2 but not present in ISO 639-1, let's just use an unassigned code
    zh       => { latin => 0, rank => 2, txt => 'Chinese' },
    'zh-Hans'=> { latin => 0, rank => 2, txt => 'Chinese (simplified)' },
    'zh-Hant'=> { latin => 0, rank => 2, txt => 'Chinese (traditional)' },
    hr       => { latin => 1, rank => 0, txt => 'Croatian' },
    cs       => { latin => 1, rank => 0, txt => 'Czech' },
    da       => { latin => 1, rank => 0, txt => 'Danish' },
    nl       => { latin => 1, rank => 0, txt => 'Dutch' },
    en       => { latin => 1, rank => 3, txt => 'English' },
    eo       => { latin => 1, rank => 0, txt => 'Esperanto' },
    et       => { latin => 1, rank => 0, txt => 'Estonian' },
    fi       => { latin => 1, rank => 0, txt => 'Finnish' },
    fr       => { latin => 1, rank => 1, txt => 'French' },
    gl       => { latin => 1, rank => 0, txt => 'Galician' },
    de       => { latin => 1, rank => 1, txt => 'German' },
    el       => { latin => 0, rank => 0, txt => 'Greek' },
    he       => { latin => 0, rank => 0, txt => 'Hebrew' },
    hi       => { latin => 0, rank => 0, txt => 'Hindi' },
    hu       => { latin => 1, rank => 0, txt => 'Hungarian' },
    ga       => { latin => 1, rank => 0, txt => 'Irish' },
    id       => { latin => 1, rank => 0, txt => 'Indonesian' },
    it       => { latin => 1, rank => 0, txt => 'Italian' },
    iu       => { latin => 1, rank => 0, txt => 'Inuktitut' },
    ja       => { latin => 0, rank => 4, txt => 'Japanese' },
    kk       => { latin => 0, rank => 0, txt => 'Kazakh' },
    ko       => { latin => 0, rank => 1, txt => 'Korean' },
    la       => { latin => 1, rank => 0, txt => 'Latin' },
    lv       => { latin => 1, rank => 0, txt => 'Latvian' },
    lt       => { latin => 1, rank => 0, txt => 'Lithuanian' },
    mk       => { latin => 1, rank => 0, txt => 'Macedonian' },
    ms       => { latin => 1, rank => 0, txt => 'Malay' },
    ne       => { latin => 0, rank => 0, txt => 'Nepali' },
    no       => { latin => 1, rank => 0, txt => 'Norwegian' },
    fa       => { latin => 0, rank => 0, txt => 'Persian' },
    pl       => { latin => 1, rank => 0, txt => 'Polish' },
    'pt-br'  => { latin => 1, rank => 1, txt => 'Portuguese (Brazil)' },
    'pt-pt'  => { latin => 1, rank => 1, txt => 'Portuguese (Portugal)' },
    ro       => { latin => 1, rank => 0, txt => 'Romanian' },
    ru       => { latin => 0, rank => 2, txt => 'Russian' },
    gd       => { latin => 1, rank => 0, txt => 'Scottish Gaelic' },
    sr       => { latin => 1, rank => 0, txt => 'Serbian' },
    sk       => { latin => 0, rank => 0, txt => 'Slovak' },
    sl       => { latin => 1, rank => 0, txt => 'Slovene' },
    es       => { latin => 1, rank => 1, txt => 'Spanish' },
    sv       => { latin => 1, rank => 0, txt => 'Swedish' },
    ta       => { latin => 1, rank => 0, txt => 'Tagalog' },
    th       => { latin => 0, rank => 0, txt => 'Thai' },
    tr       => { latin => 1, rank => 0, txt => 'Turkish' },
    uk       => { latin => 0, rank => 1, txt => 'Ukrainian' },
    ur       => { latin => 0, rank => 0, txt => 'Urdu' },
    vi       => { latin => 1, rank => 1, txt => 'Vietnamese' };



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
    sw2 => 'Nintendo Switch 2',
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


hash DRM_PROPERTY => # No DRM: https://lucide.dev/icons/unlock (needs circle?)
    disc      => 'Disc check',        # https://lucide.dev/icons/disc-3
    cdkey     => 'CD-key',            # https://lucide.dev/icons/key-round (needs circle?)
    activate  => 'Online activation', # https://lucide.dev/icons/wifi (needs circle?)
    alimit    => 'Activation limit',
    account   => 'Account-based',     # https://lucide.dev/icons/link  (needs circle?)
    online    => 'Always online',
    cloud     => 'Cloud gaming',
    physical  => 'Physical';  # XXX: How does this relate to cdkey?


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
hash ANIME_TYPE =>
    tv  => 'TV Series',
    ova => 'OVA',
    mov => 'Movie',
    oth => 'Other',
    web => 'Web',
    spe => 'TV Special',
    mv  => 'Music Video';



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
    blr => { qty => 1, txt => 'Blu-ray disc',          plural => 'Blu-ray discs',          icon => 'disk'      },
    mrt => { qty => 1, txt => 'Cartridge',             plural => 'Cartridges',             icon => 'cartridge' },
    cas => { qty => 1, txt => 'Cassette tape',         plural => 'Cassette tapes',         icon => 'cartridge' },
    cd  => { qty => 1, txt => 'CD',                    plural => 'CDs',                    icon => 'disk'      },
    dc  => { qty => 0, txt => 'Download card',         plural => '',                       icon => 'download'  },
    dvd => { qty => 1, txt => 'DVD',                   plural => 'DVDs',                   icon => 'disk'      },
    flp => { qty => 1, txt => 'Floppy',                plural => 'Floppies',               icon => 'cartridge' },
    gdr => { qty => 1, txt => 'GD-ROM',                plural => 'GD-ROMs',                icon => 'disk'      },
    in  => { qty => 0, txt => 'Internet download',     plural => '',                       icon => 'download'  },
    mem => { qty => 1, txt => 'Memory card',           plural => 'Memory cards',           icon => 'cartridge' },
    nod => { qty => 1, txt => 'Nintendo Optical Disc', plural => 'Nintendo Optical Discs', icon => 'disk'      },
    umd => { qty => 1, txt => 'UMD',                   plural => 'UMDs',                   icon => 'disk'      },
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



# SQL: ENUM staff_gender
hash STAFF_GENDER =>
    '' => 'Unknown or N/A',
    m  => 'Male',
    f  => 'Female';



# SQL: ENUM staff_type
hash STAFF_TYPE =>
    person  => 'Person',
    group   => 'Group',
    company => 'Company',
    repo    => 'Repository';



# SQL: ENUM char_sex
hash CHAR_SEX =>
    '' => 'Unknown',
    m  => 'Male',
    f  => 'Female',
    b  => 'Both',
    n  => 'Sexless';



# SQL: ENUM char_gender
hash CHAR_GENDER =>
    '' => 'Unknown',
    m  => 'Man',
    f  => 'Woman',
    o  => 'Non-binary',
    a  => 'Ambiguous';



# SQL: ENUM cup_size
hash CUP_SIZE =>
    ''  => 'Unknown or N/A',
    AAA => 'AAA',
    AA  => 'AA',
    map +($_,$_), 'A'..'Z';



# SQL: ENUM release_image_type
hash RELEASE_IMAGE_TYPE =>
    pkgfront   => { ord => 1, txt => 'Package (front)' },
    pkgback    => { ord => 3, txt => 'Package (back)' },
    pkgcontent => { ord => 4, txt => 'Package (contents)' },
    pkgside    => { ord => 5, txt => 'Package (side)' },
    pkgmed     => { ord => 6, txt => 'Media' },
    dig        => { ord => 2, txt => 'Digital promo art' };



# SQL: ENUM char_role
hash CHAR_ROLE =>
    main    => { txt => 'Protagonist',         plural => 'Protagonists'       },
    primary => { txt => 'Main character',      plural => 'Main characters'    },
    side    => { txt => 'Side character',      plural => 'Side characters'    },
    appears => { txt => 'Makes an appearance', plural => 'Make an appearance' };



# Change flags for database entries, up to 63 categories can be listed per type.
# The first category is hardcoded to refer to the hidden/locked flags.
# Array indices are used as category identifier in the database and in URLs,
# changing order or semantics requires a cache rebuild. (And may break some
# urls, but these aren't the type of URLs where stability is super important)
# (Support for placeholder entries can be added later on if we ever want some
# flexibility to avoid rebuilds and breakage)
hash CHFLAGS =>
    v => [qw[
        Modflags
        Title
        Language
        Image
        Links
        Description
        Status
        Length
        Anime
        Relations
        Screenshots
        VA
        Staff
    ]],
    r => [qw[
        Modflags
        Title
        Language
        Image
        Links
        Date
        Voiced
        Resolution
        AgeRating
        Ero
        Publication
        Engine
        Notes
        Media
        Platforms
        Animation
        Identifiers
        VN
        DRM
        Producers
        Supersedes
    ]],
    p => [qw[
        Modflags
        Name
        Description
        Type
        Language
        Links
        Relations
    ]],
    c => [qw[
        Modflags
        Name
        Description
        Image
        Age
        Gender
        Measurements
        BloodType
        Main
        Traits
        VN
    ]],
    s => [qw[
        Modflags
        Name
        Language
        Description
        Gender
        Links
        Producer
        Type
    ]],
    d => [qw[Modflags Title Content]],
    g => [qw[
        Modflags
        Name
        Category
        Description
        Flags
        Parent
    ]],
    i => [qw[
        Modflags
        Name
        Description
        Flags
        Parent
    ]];


# Concise implementation of an immutable hash that remembers key order.
package VNDB::Types::Hash;
use v5.36;
sub TIEHASH { shift; bless [ [ map $_[$_*2], 0..$#_/2 ], +{@_}, 0 ], __PACKAGE__ };
sub FETCH { $_[0][1]{$_[1]} }
sub EXISTS { exists $_[0][1]{$_[1]} }
sub FIRSTKEY { $_[0][2] = 0; &NEXTKEY }
sub NEXTKEY { $_[0][0][ $_[0][2]++ ] }
sub SCALAR { scalar $_[0][0]->@* }
1;
