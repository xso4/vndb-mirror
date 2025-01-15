package VNDB::ExtLinks;

use v5.36;
use VNDB::Config;
use VNDB::Schema;
use Exporter 'import';

our @EXPORT = ('enrich_vislinks');


# column name in wikidata table => \%info
# info keys:
#   type       SQL type, used by Multi to generate the proper SQL
#   property   Wikidata Property ID, used by Multi
#   label      How the link is displayed on the website
#   fmt        How to generate the url (printf-style string or subroutine returning the full URL)
our %WIKIDATA = (
    enwiki             => { type => 'text',       property => undef,   label => 'Wikipedia (en)', fmt => sub { sprintf 'https://en.wikipedia.org/wiki/%s', (shift =~ s/ /_/rg) =~ s/\?/%3f/rg } },
    jawiki             => { type => 'text',       property => undef,   label => 'Wikipedia (ja)', fmt => sub { sprintf 'https://ja.wikipedia.org/wiki/%s', (shift =~ s/ /_/rg) =~ s/\?/%3f/rg } },
    website            => { type => 'text[]',     property => 'P856',  label => undef,            fmt => undef },
    vndb               => { type => 'text[]',     property => 'P3180', label => undef,            fmt => undef },
    mobygames          => { type => 'text[]',     property => 'P1933', label => 'MobyGames',      fmt => 'https://www.mobygames.com/game/%s' },
    mobygames_company  => { type => 'text[]',     property => 'P4773', label => 'MobyGames',      fmt => 'https://www.mobygames.com/company/%s' },
    gamefaqs_game      => { type => 'integer[]',  property => 'P4769', label => 'GameFAQs',       fmt => 'https://gamefaqs.gamespot.com/-/%s-' },
    gamefaqs_company   => { type => 'integer[]',  property => 'P6182', label => 'GameFAQs',       fmt => 'https://gamefaqs.gamespot.com/company/%s-' },
    anidb_anime        => { type => 'integer[]',  property => 'P5646', label => undef,            fmt => undef },
    anidb_person       => { type => 'integer[]',  property => 'P5649', label => 'AniDB',          fmt => 'https://anidb.net/cr%s' },
    ann_anime          => { type => 'integer[]',  property => 'P1985', label => undef,            fmt => undef },
    ann_manga          => { type => 'integer[]',  property => 'P1984', label => undef,            fmt => undef },
    musicbrainz_artist => { type => 'uuid[]',     property => 'P434',  label => 'MusicBrainz',    fmt => 'https://musicbrainz.org/artist/%s' },
    twitter            => { type => 'text[]',     property => 'P2002', label => 'Xitter',         fmt => 'https://x.com/%s' },
    vgmdb_product      => { type => 'integer[]',  property => 'P5659', label => 'VGMdb',          fmt => 'https://vgmdb.net/product/%s' },
    vgmdb_artist       => { type => 'integer[]',  property => 'P3435', label => 'VGMdb',          fmt => 'https://vgmdb.net/artist/%s' },
    discogs_artist     => { type => 'integer[]',  property => 'P1953', label => 'Discogs',        fmt => 'https://www.discogs.com/artist/%s' },
    acdb_char          => { type => 'integer[]',  property => 'P7013', label => undef,            fmt => undef },
    acdb_source        => { type => 'integer[]',  property => 'P7017', label => 'ACDB',           fmt => 'https://www.animecharactersdatabase.com/source.php?id=%s' },
    indiedb_game       => { type => 'text[]',     property => 'P6717', label => 'IndieDB',        fmt => 'https://www.indiedb.com/games/%s' },
    howlongtobeat      => { type => 'integer[]',  property => 'P2816', label => 'HowLongToBeat',  fmt => 'http://howlongtobeat.com/game.php?id=%s' },
    crunchyroll        => { type => 'text[]',     property => 'P4110', label => undef,            fmt => undef },
    igdb_game          => { type => 'text[]',     property => 'P5794', label => 'IGDB',           fmt => 'https://www.igdb.com/games/%s' },
    giantbomb          => { type => 'text[]',     property => 'P5247', label => undef,            fmt => undef },
    pcgamingwiki       => { type => 'text[]',     property => 'P6337', label => 'PCGamingWiki',   fmt => 'https://www.pcgamingwiki.com/wiki/%s' },
    steam              => { type => 'integer[]',  property => 'P1733', label => undef,            fmt => undef },
    gog                => { type => 'text[]',     property => 'P2725', label => 'GOG',            fmt => 'https://www.gog.com/game/%s' },
    pixiv_user         => { type => 'integer[]',  property => 'P5435', label => 'Pixiv',          fmt => 'https://www.pixiv.net/member.php?id=%d' },
    doujinshi_author   => { type => 'integer[]',  property => 'P7511', label => 'Doujinshi.org',  fmt => 'https://www.doujinshi.org/browse/author/%d/' },
    soundcloud         => { type => 'text[]',     property => 'P3040', label => 'Soundcloud',     fmt => 'https://soundcloud.com/%s' },
    humblestore        => { type => 'text[]',     property => 'P4477', label => undef,            fmt => undef },
    itchio             => { type => 'text[]',     property => 'P7294', label => undef,            fmt => undef },
    playstation_jp     => { type => 'text[]',     property => 'P5999', label => undef,            fmt => undef },
    playstation_na     => { type => 'text[]',     property => 'P5944', label => undef,            fmt => undef },
    playstation_eu     => { type => 'text[]',     property => 'P5971', label => undef,            fmt => undef },
    lutris             => { type => 'text[]',     property => 'P7597', label => 'Lutris',         fmt => 'https://lutris.net/games/%s' },
    wine               => { type => 'integer[]',  property => 'P600',  label => 'Wine AppDB',     fmt => 'https://appdb.winehq.org/appview.php?iAppId=%d' },
);


# Captures a decimal integer, accepting but removing any leading zeros
my $int = qr/0*([1-9][0-9]*)/;

# extlink_site => \%info
# Site names are also exposed in the API and used for AdvSearch filters, so they should be stable.
# %info keys:
#   ent       Applicable DB entry types; String with id-prefixes, uppercase if multiple links are permitted for this site.
#   label     Name of the link
#   fmt       How to generate a url (basic version, printf-style only)
#   fmt2      How to generate a better url
#             (printf-style string or subroutine, given a hashref of the DB entry and returning a new 'fmt' string)
#             ("better" meaning proper store section, affiliate link)
#   regex     Regex to detect a URL and extract the database value (the first non-empty placeholder).
#             Excludes a leading qr{^https?://} match and is anchored on both sites, see 'full_regex' assignment below.
#             (A valid DB value must survive a 'fmt' -> 'regex' round trip)
#             (Only set for links that should be autodetected in the edit form)
#   patt      Human-readable URL pattern that corresponds to 'fmt' and 'regex'; Automatically derived from 'fmt' if not set.
our %LINKS = (
    anidb =>
        { ent   => 's'
        , label => 'AniDB'
        , fmt   => 'https://anidb.net/cr%s'
        , regex => qr{anidb\.net/(?:cr|creator/)$int}
        },
    animateg =>
        { ent   => 'r'
        , label => 'Animate Games'
        , fmt   => 'https://www.animategames.jp/home/detail/%d'
        , regex => qr{(?:www\.)?animategames\.jp/home/detail/$int}
        },
    anison =>
        { ent   => 's'
        , label => 'Anison'
        , fmt   => 'http://anison.info/data/person/%d.html'
        , regex => qr{anison\.info/data/person/$int\.html}
        },
    appstore =>
        { ent   => 'r'
        , label => 'App Store'
        , fmt   => 'https://apps.apple.com/%s'
        , regex => qr{(?:itunes|apps)\.apple\.com/((?:[^/]+/)?app/(?:[^/]+/)?id$int)(?:[/\?].*)?}
        },
    bgmtv =>
        { ent   => 's'
        , label => 'Bangumi'
        , fmt   => 'https://bgm.tv/person/%d'
        , regex => qr{(?:www\.)?(?:bgm|bangumi)\.tv/person/$int(?:[?/].*)?}
        },
    boosty =>
        { ent   => 'sp'
        , label => 'Boosty'
        , fmt   => 'https://boosty.to/%s'
        , regex => qr{boosty\.to/([a-z0-9_.]+)/?}
        },
    booth =>
        { ent   => 'r'
        , label => 'BOOTH'
        , fmt   => 'https://booth.pm/en/items/%d'
        , regex => qr{(?:[a-z0-9_-]+\.)?booth\.pm/(?:[a-z-]+\/)?items/$int.*}
        , patt  => 'https://booth.pm/<language>/items/<id>  OR  https://<publisher>.booth.pm/items/<id>'
        },
    denpa =>
        { ent   => 'r'
        , label => 'Denpasoft'
        , fmt   => 'https://denpasoft.com/product/%s/'
        , fmt2  => config->{denpa_url}
        , regex => qr{(?:www\.)?denpasoft\.com/products?/([^/&#?:]+).*}
        },
    deviantar =>
        { ent   => 's'
        , label => 'DeviantArt'
        , fmt   => 'https://www.deviantart.com/%s'
        , regex => qr{(?:([a-z0-9-]+)\.deviantart\.com/?|(?:www\.)?deviantart\.com/([^/?]+)(?:[?/].*)?)}
        },
    digiket =>
        { ent   => 'r'
        , label => 'Digiket'
        , fmt   => 'https://www.digiket.com/work/show/_data/ID=ITM%07d/'
        , regex => qr{(?:www\.)?digiket\.com/.*ITM$int.*}
        },
    discogs =>
        { ent   => 's'
        , label => 'Discogs'
        , fmt   => 'https://www.discogs.com/artist/%d'
        , regex => qr{(?:www\.)?discogs\.com/artist/$int(?:[?/-].*)?}
        },
    dlsite =>
        { ent   => 'r'
        , label => 'DLsite',
        , fmt   => 'https://www.dlsite.com/home/work/=/product_id/%s.html'
        , fmt2  => sub { config->{dlsite_url} && sprintf config->{dlsite_url}, shift->{data}||'home' }
        , regex => qr{(?:www\.)?dlsite\.com/.*/(?:dlaf/=/link/work/aid/.*/id|work/=/product_id)/([VR]J[0-9]{6,8}).*}
        , patt  => 'https://www.dlsite.com/<store>/work/=/product_id/<VJ or RJ-code>'
        },
    dlsiteen => # Deprecated, stores have been merged.
        { ent   => 'r'
        , label => 'DLsite (eng)'
        , fmt   => 'https://www.dlsite.com/eng/work/=/product_id/%s.html'
        },
    dmm =>
        { ent   => 'R'
        , label => 'DMM'
        , fmt   => 'https://%s'
        , regex => qr{((?:www\.|dlsoft\.)?dmm\.(?:com|co\.jp)/[^\s?]+)(?:\?.*)?}
        , patt  => 'https://<any link to dmm.com or dmm.co.jp>'
        },
    egs =>
        { ent   => 'r'
        , label => 'ErogameScape'
        , fmt   => 'https://erogamescape.dyndns.org/~ap2/ero/toukei_kaiseki/game.php?game=%d'
        , regex => qr{erogamescape\.dyndns\.org/~ap2/ero/toukei_kaiseki/(?:before_)?game\.php\?(?:.*&)?game=$int(?:&.*)?}
        },
    egs_creator =>
        { ent   => 's'
        , label => 'ErogameScape'
        , fmt   => 'https://erogamescape.dyndns.org/~ap2/ero/toukei_kaiseki/creater.php?creater=%d'
        , regex => qr{erogamescape\.dyndns\.org/~ap2/ero/toukei_kaiseki/(?:before_)?creater\.php\?(?:.*&)?creater=$int(?:&.*)?}
        },
    erotrail => # Deprecated, site has been unavailable since early 2022.
        { ent   => 'r'
        , label => 'ErogeTrailers'
        , fmt   => 'http://erogetrailers.com/soft/%d'
        },
    facebook =>
        { ent   => 'sp'
        , label => 'Facebook'
        , fmt   => 'https://www.facebook.com/%s'
        , regex => qr{(?:www\.)?facebook\.com/([a-zA-Z0-9.-]+)/?(:?\?.*)?},
        },
    fakku =>
        { ent   => 'r'
        , label => 'Fakku'
        , fmt   => 'https://www.fakku.net/games/%s'
        , regex => qr{(?:www\.)?fakku\.(?:net|com)/games/([^/]+)(?:[/\?].*)?}
        },
    freegame =>
        { ent   => 'r'
        , label => 'Freegame Mugen'
        , fmt   => 'https://freegame-mugen.jp/%s.html'
        , regex => qr{(?:www\.)?freegame-mugen\.jp/([^/]+/game_[0-9]+)\.html}
        , patt  => 'https://freegame-mugen.jp/<genre>/game_<id>.html'
        },
    freem =>
        { ent   => 'r'
        , label => 'Freem!'
        , fmt   => 'https://www.freem.ne.jp/win/game/%d'
        , regex => qr{(?:www\.)?freem\.ne\.jp/win/game/$int}
        },
    gamefaqs_comp =>
        { ent   => 'p'
        , label => 'GameFAQs'
        , fmt   => 'https://gamefaqs.gamespot.com/company/%d-'
        , regex => qr{(?:www\.)?gamefaqs\.gamespot\.com/(?:games/)?company/$int-.*}
        },
    gamejolt =>
        { ent   => 'r'
        , label => 'Game Jolt'
        , fmt   => 'https://gamejolt.com/games/vn/%d', # /vn/ should be the game title, but it doesn't matter
        , regex => qr{(?:www\.)?gamejolt\.com/games/(?:[^/]+)/$int(?:/.*)?}
        },
    getchu =>
        { ent   => 'r'
        , label => 'Getchu'
        , fmt   => 'http://www.getchu.com/soft.phtml?id=%d'
        , regex => qr{(?:www\.)?getchu\.com/soft\.phtml\?id=$int.*}
        },
    getchudl =>
        { ent   => 'r'
        , label => 'DL.Getchu'
        , fmt   => 'http://dl.getchu.com/i/item%d'
        , regex => qr{(?:dl|order)\.getchu\.com/(?:i/item|(?:r|index).php.*[?&]gcd=D?)$int.*}
        },
    gog =>
        { ent   => 'r'
        , label => 'GOG',
        , fmt   => 'https://www.gog.com/game/%s'
        , regex => qr{(?:www\.)?gog\.com/(?:[a-z]{2}/)?game/([a-z0-9_]+).*}
        },
    googplay =>
        { ent   => 'r'
        , label => 'Google Play'
        , fmt   => 'https://play.google.com/store/apps/details?id=%s'
        , regex => qr{play\.google\.com/store/apps/details\?id=([^/&\?]+)(?:&.*)?}
        },
    gyutto =>
        { ent   => 'R'
        , label => 'Gyutto'
        , fmt   => 'https://gyutto.com/i/item%d'
        , regex => qr{(?:www\.)?gyutto\.(?:com|jp|me)/(?:.+\/)?i/item$int.*}
        },
    imdb =>
        { ent   => 's'
        , label => 'IMDb'
        , fmt   => 'https://www.imdb.com/name/nm%07d'
        , regex => qr{(?:www\.)?imdb\.com/name/nm$int(?:[?/].*)?}
        },
    instagram =>
        { ent   => 'sp'
        , label => 'Instagram'
        , fmt   => 'https://www.instagram.com/%s/'
        , regex => qr{(?:www\.)?instagram\.com/([^/?]+)(?:[?/].*)?}
        },
    itch =>
        { ent   => 'r'
        , label => 'Itch.io'
        , fmt   => 'https://%s'
        , regex => qr{([a-z0-9_-]+\.itch\.io/[a-z0-9_-]+)}
        , patt  => 'https://<artist>.itch.io/<product>'
        },
    itch_dev =>
        { ent   => 'sp'
        , label => 'Itch.io'
        , fmt   => 'https://%s.itch.io/'
        , regex => qr{(?:([a-z0-9_-]+)\.itch\.io/.*|itch\.io/profile/([a-z0-9_-]+))}
        },
    jastusa =>
        { ent   => 'r'
        , label => 'JAST USA'
        , fmt   => 'https://jastusa.com/games/%s/vndb'
        , fmt2  => sub { config->{jastusa_url} && sprintf config->{jastusa_url}, shift->{data}||'vndb' },
        , regex => qr{(?:www\.)?jastusa\.com/games/([a-z0-9_-]+)/[^/]+}
        , patt  => 'https://jastusa.com/games/<code>/<title>'
        },
    jlist =>
        { ent   => 'r'
        , label => 'J-List'
        , fmt   => 'https://www.jlist.com/shop/product/%s'
        , fmt2  => config->{jlist_url},
        , regex => qr{(?:www\.)?(?:jlist|jbox)\.com/shop/product/([^/#?]+).*}
        },
    kofi =>
        { ent   => 's'
        , label => 'Ko-fi'
        , fmt   => 'https://ko-fi.com/%s'
        , regex => qr{(?:www\.)?ko-fi\.com/([^/?]+)(?:[?/].*)?}
        },
    mbrainz =>
        { ent   => 's'
        , label => 'MusicBrainz'
        , fmt   => 'https://musicbrainz.org/artist/%s'
        , regex => qr{musicbrainz\.org/artist/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})}
        },
    melon =>
        { ent   => 'r'
        , label => 'Melonbooks.com'
        , fmt   => 'https://www.melonbooks.com/index.php?main_page=product_info&products_id=IT%010d'
        , regex => qr{(?:www\.)?melonbooks\.com/.*products_id=IT$int.*}
        },
    melonjp =>
        { ent   => 'r'
        , label => 'Melonbooks.co.jp'
        , fmt   => 'https://www.melonbooks.co.jp/detail/detail.php?product_id=%d',
        , regex => qr{(?:www\.)?melonbooks\.co\.jp/detail/detail\.php\?product_id=$int(&:?.*)?}
        },
    mg =>
        { ent   => 'r'
        , label => 'MangaGamer'
        , fmt   => 'https://www.mangagamer.com/r18/detail.php?product_code=%d'
        , fmt2  => sub { config->{ $_[0]{data} ? 'mg_main_url' : 'mg_r18_url' } }
        , regex => qr{(?:www\.)?mangagamer\.com/.*product_code=$int.*}
        },
    mobygames =>
        { ent   => 's'
        , label => 'MobyGames'
        , fmt   => 'https://www.mobygames.com/person/%d'
        , regex => qr{(?:www\.)?mobygames\.com/person/$int(?:[?/].*)?}
        },
    mobygames_comp =>
        { ent   => 'p'
        , label => 'MobyGames'
        , fmt   => 'https://www.mobygames.com/company/%d'
        , regex => qr{(?:www\.)?mobygames\.com/company/$int(?:[?/].*)?}
        },
    nintendo =>
        { ent   => 'r'
        , label => 'Nintendo'
        , fmt   => 'https://www.nintendo.com/store/products/%s/'
        , regex => qr{www\.nintendo\.com\/store\/products\/([-a-z0-9]+)\/}
        },
    nintendo_hk =>
        { ent   => 'r'
        , label => 'Nintendo (HK)'
        , fmt   => 'https://store.nintendo.com.hk/%d'
        , regex => qr{store\.nintendo\.com\.hk/$int}
        },
    nintendo_jp =>
        { ent   => 'r'
        , label => 'Nintendo (JP)'
        , fmt   => 'https://store-jp.nintendo.com/item/software/D%d'
        , regex => qr{store-jp\.nintendo\.com/(?:item|list)/software/D?$int(?:\.html)?}
        },
    novelgam =>
        { ent   => 'r'
        , label => 'NovelGame'
        , fmt   => 'https://novelgame.jp/games/show/%d'
        , regex => qr{(?:www\.)?novelgame\.jp/games/show/$int}
        },
    nutaku =>
        { ent   => 'r'
        , label => 'Nutaku'
        , fmt   => 'https://www.nutaku.net/games/%s/'
        # The section part does sometimes link to different pages, but it's the same game and the non-section link always works.
        , regex => qr{(?:www\.)?nutaku\.net/games/(?:mobile/|download/|app/)?([a-z0-9-]+)/?}
        },
    patreon =>
        { ent   => 'rsp'
        , label => 'Patreon'
        , fmt   => 'https://www.patreon.com/%s'
        , regex => qr{(?:www\.)?patreon\.com/(?:c/)?(?!user[\?/]|posts[\?/]|join[\?/])([^/?]+).*}
        },
    patreonp =>
        { ent   => 'r'
        , label => 'Patreon post'
        , fmt   => 'https://www.patreon.com/posts/%d'
        , regex => qr{(?:www\.)?patreon\.com/posts/(?:[^/?]+-)?$int.*}
        },
    pixiv =>
        { ent   => 'sp'
        , label => 'Pixiv'
        , fmt   => 'https://www.pixiv.net/member.php?id=%d'
        , regex => qr{www\.pixiv\.net/(?:member\.php\?id=|en/users/|users/)$int}
        },
    playstation_eu =>
        { ent   => 'r'
        , label => 'PlayStation Store (EU)'
        , fmt => 'https://store.playstation.com/en-gb/product/%s'
        , regex => qr{store\.playstation\.com/(?:[-a-z]+\/)?product\/(EP\d{4}-[A-Z]{4}\d{5}_00-[\dA-Z_]{16})}
        },
    playstation_hk =>
        { ent   => 'r'
        , label => 'PlayStation Store (HK)'
        , fmt => 'https://store.playstation.com/en-hk/product/%s'
        , regex => qr{store\.playstation\.com/(?:[-a-z]+\/)?product\/(HP\d{4}-[A-Z]{4}\d{5}_00-[\dA-Z_]{16})}
        },
    playstation_jp =>
        { ent   => 'r'
        , label => 'PlayStation Store (JP)'
        , fmt => 'https://store.playstation.com/ja-jp/product/%s'
        , regex => qr{store\.playstation\.com/(?:[-a-z]+\/)?product\/(JP\d{4}-[A-Z]{4}\d{5}_00-[\dA-Z_]{16})}
        },
    playstation_na =>
        { ent   => 'r'
        , label => 'PlayStation Store (NA)'
        , fmt => 'https://store.playstation.com/en-us/product/%s'
        , regex => qr{store\.playstation\.com/(?:[-a-z]+\/)?product\/(UP\d{4}-[A-Z]{4}\d{5}_00-[\dA-Z_]{16})}
        },
    renai => # Not in SQL extlink_site enum, VN entries don't use that (yet)
        { ent   => 'v'
        , label => 'Renai.us'
        , fmt   => 'https://renai.us/game/%s'
        },
    scloud =>
        { ent   => 'sp'
        , label => 'SoundCloud'
        , fmt   => 'https://soundcloud.com/%s'
        , regex => qr{soundcloud\.com/([a-z0-9_-]+)}
        },
    steam =>
        { ent   => 'r'
        , label => 'Steam'
        , fmt   => 'https://store.steampowered.com/app/%d/'
        , fmt2  => 'https://store.steampowered.com/app/%d/?utm_source=vndb'
        , regex => qr{(?:www\.)?(?:store\.steampowered\.com/app/$int(?:/.*)?|steamcommunity\.com/(?:app|games)/$int(?:/.*)?|steamdb\.info/app/$int(?:/.*)?)}
        },
    substar =>
        { ent   => 'rsp'
        , label => 'SubscribeStar'
        , fmt   => 'https://subscribestar.%s'
        , regex => qr{(?:www\.)?subscribestar\.((?:adult|com)/[^/?]+).*}
        , patt  => 'https://subscribestar.<adult or com>/<name>'
        },
    toranoana =>
        { ent   => 'r'
        , label => 'Toranoana'
        # ec.* is for 18+, ecs.toranoana.jp is for non-18+.
        # ec.toranoana.shop will redirect to ecs.* as appropriate for the product ID, but ec.toranoana.jp won't.
        , fmt   => 'https://ec.toranoana.shop/tora/ec/item/%012d/'
        , regex => qr{(?:www\.)?ecs?\.toranoana\.(?:shop|jp)/(?:aqua/ec|(?:tora|joshi)(?:/ec|_r/ec|_d/digi|_rd/digi)?)/item/$int.*}
        , patt  => 'https://ec.toranoana.<shop or jp>/<shop>/item/<number>/'
        },
    tumblr =>
        { ent   => 's'
        , label => 'Tumblr'
        , fmt   => 'https://%s.tumblr.com/'
        , regex => qr{([a-z0-9-]+)\.tumblr\.com/.*}
        },
    twitter =>
        { ent   => 'SP',
        , label => 'Xitter'
        , fmt   => 'https://x.com/%s'
        , regex => qr{(?:(?:www\.)?(?:x|twitter)\.com|nitter\.[^/]+)/([^?\/ ]{1,16})(?:[?/].*)?}
        },
    vgmdb =>
        { ent   => 's'
        , label => 'VGMdb'
        , fmt   => 'https://vgmdb.net/artist/%d'
        , regex => qr{vgmdb\.net/artist/$int}
        },
    vk =>
        { ent   => 'sp'
        , label => 'VK'
        , fmt   => 'https://vk.com/%s'
        , regex => qr{vk\.com/([a-zA-Z0-9_.]+)}
        },
    vndb =>
        { ent   => 's'
        , label => 'VNDB user'
        , fmt   => 'https://vndb.org/%s'
        , regex => qr{vndb\.org/(u[1-9][0-9]*)}
        },
    website => # Official website, catch-all
        { ent   => 'rsp'
        , label => 'Official website'
        , fmt   => '%s'
        },
    wikidata =>
        { ent   => 'sp'
        , label => 'Wikidata'
        , fmt   => 'https://www.wikidata.org/wiki/Q%d'
        , regex => qr{(?:www\.)?wikidata\.org/wiki/(?:Special:EntityPage/)?Q$int}
        },
    wp => # Deprecated, replaced with wikidata
        { ent => 'rsp'
        , label => 'Wikipedia'
        , fmt => 'https://en.wikipedia.org/wiki/%s'
        },
    youtube =>
        { ent   => 'sp'
        , label => 'Youtube'
        # There's also /user/<name> syntax, but <name> may be different in this form *sigh*.
        , fmt   => 'https://www.youtube.com/@%s'
        , regex => qr{(?:www\.)?youtube\.com/@([^/?]+)}
        },
);


$_->{full_regex} = qr{^(?:https?://)?$_->{regex}(?:\#.*)?$} for grep $_->{regex}, values %LINKS;


# For VN entries, which have visible links but no proper extlinks table yet.
sub enrich_vislinks_old($type, $enabled, @obj) {
    my @w_ids = grep $_, map $_->{l_wikidata}, @obj;
    my $w = @w_ids ? { map +($_->{id}, $_), $TUWF::OBJ->dbAlli('SELECT * FROM wikidata WHERE id IN', \@w_ids)->@* } : {};

    for my $obj (@obj) {
        my @links;
        my sub w {
            return if !$obj->{l_wikidata};
            my($v, $fmt, $label) = ($w->{$obj->{l_wikidata}}{$_[0]}, @{$WIKIDATA{$_[0]}}{'fmt', 'label'});
            push @links, map +{
                $enabled->{name}  ? (name  => $_[0]) : (),
                $enabled->{label} ? (label => $label) : (),
                $enabled->{id}    ? (id    => $_) : (),
                $enabled->{url}   ? (url   => ref $fmt ? $fmt->($_) : sprintf $fmt, $_) : (),
                $enabled->{url2}  ? (url2  => ref $fmt ? $fmt->($_) : sprintf $fmt, $_) : (),
            }, ref $v ? @$v : $v ? $v : ()
        }
        my sub l {
            my($f, $price) = @_;
            my($v, $fmt, $fmt2, $label) = ($obj->{$f}, @{$LINKS{ $f =~ s/^l_//r }}{'fmt', 'fmt2', 'label'});
            push @links, map +{
                $enabled->{name}  ? (name  => $f =~ s/^l_//r) : (),
                $enabled->{label} ? (label => $label) : (),
                $enabled->{id}    ? (id    => $_) : (),
                $enabled->{url}   ? (url   => sprintf($fmt, $_)) : (),
                $enabled->{url2}  ? (url2  => sprintf((ref $fmt2 ? $fmt2->($obj) : $fmt2) || $fmt, $_)) : (),
                $enabled->{price} && length $price ? (price => $price) : (),
            }, ref $v ? @$v : $v ? $v : ()
        }
        my sub c {
            my($name, $label, $fmt, $id, $price) = @_;
            push @links, {
                $enabled->{name}  ? (name  => $name) : (),
                $enabled->{label} ? (label => $label) : (),
                $enabled->{id}    ? (id    => $id) : (),
                $enabled->{url}   ? (url   => sprintf($fmt, $id)) : (),
                $enabled->{url2}  ? (url2  => sprintf($fmt, $id)) : (),
                $enabled->{price} && length $price ? (price => $price) : (),
            }
        }

        w 'enwiki';
        w 'jawiki';
        l 'l_wikidata';
        w 'mobygames';
        w 'gamefaqs_game';
        w 'vgmdb_product';
        w 'acdb_source';
        w 'indiedb_game';
        w 'howlongtobeat';
        w 'igdb_game';
        w 'pcgamingwiki';
        w 'lutris';
        w 'wine';
        l 'l_renai';
        c 'vnstat', 'VNStat', 'https://vnstat.net/novel/%d', $obj->{id} =~ s/^.//r if ($obj->{c_votecount}||0) >= 20;

        $obj->{vislinks} = \@links;
    }
}


# Fetch a list of links to display at the given database entries, adds the
# following field to each object:
#
#   vislinks => [
#     { name, label, id, url, url2, price },  # depending on which fields are $enabled
#     ..
#   ]
sub enrich_vislinks($type, $enabled, @obj) {
    $enabled ||= { name => 1, label => 1, url2 => 1, price => 1 };
    @obj = map ref $_ eq 'ARRAY' ? @$_ : ($_), @obj;
    return if !@obj;

    return enrich_vislinks_old $type, $enabled, @obj if $type =~ /v/;

    my @w_ids;
    my %ids = map {
        my $o = $_;
        $o->{vislinks} = [];
        for ($o->{extlinks} ? $o->{extlinks}->@* : ()) {
            push $o->{_l}{$_->{site}}->@*, $_;
            push @w_ids, $_->{value} if $_->{site} eq 'wikidata';
        }
        +($o->{id}, $_)
    } @obj;
    my @ids = keys %ids;

    # Fetch extlinks for objects that do not already have an 'extlinks' field
    my @ids_ne = grep !$ids{$_}{extlinks}, @ids;
    for my $s (@ids_ne ? $TUWF::OBJ->dbAlli('
        SELECT e.id, l.site, l.value, l.data, l.price
          FROM', {qw/r releases_extlinks  s staff_extlinks  p producers_extlinks/}->{$type}, 'e
          JOIN extlinks l ON l.id = e.link
         WHERE e.id IN', \@ids_ne
    )->@* : ()) {
        push $ids{$s->{id}}{_l}{$s->{site}}->@*, $s;
        push @w_ids, $s->{value} if $s->{site} eq 'wikidata';
    }

    my $w = @w_ids ? { map +($_->{id}, $_), $TUWF::OBJ->dbAlli('SELECT * FROM wikidata WHERE id IN', \@w_ids)->@* } : {};

    push $ids{$_->{id}}{_l}{_playasia}->@*, $_ for ($type eq 'r' ? $TUWF::OBJ->dbAlli(
        "SELECT r.id, s.price, s.url FROM releases r JOIN shop_playasia s ON s.gtin = r.gtin WHERE s.price <> '' AND r.id IN", \@ids
    )->@* : ());

    my $o;
    my sub c($name, $label, $id, $url, $url2=undef, $price=undef) {
        push $o->{vislinks}->@*, {
            $enabled->{name}  ? (name  => $name ) : (),
            $enabled->{label} ? (label => $label) : (),
            $enabled->{id}    ? (id    => $id   ) : (),
            $enabled->{url}   ? (url   => $url  ) : (),
            $enabled->{url2}  ? (url2  => $url2 || $url) : (),
            $enabled->{price} && length $price ? (price => $price) : (),
        }
    }
    my sub l($f) {
        my $l = $LINKS{$f};
        c $f, $l->{label}, $_->{value}, sprintf($l->{fmt}, $_->{value}),
            sprintf((ref $l->{fmt2} ? $l->{fmt2}->($_) : $l->{fmt2}) || $l->{fmt}, $_->{value}),
            $_->{price} for $o->{_l}{$f} ? $o->{_l}{$f}->@* : ();
    }
    my sub w($f) {
        return if !$o->{_l}{wikidata};
        my $v = $w->{ $o->{_l}{wikidata}[0]{value} }{$f};
        my $l = $WIKIDATA{$f};
        c $f, $l->{label}, $_, ref $l->{fmt} ? $l->{fmt}->($_) : sprintf($l->{fmt}, $_)
            for ref $v ? @$v : $v ? $v : ();
    }

    for ($type eq 'r' ? @obj : ()) {$o=$_;
        l 'website';
        l 'egs';
        l 'steam';
        c 'steamdb', 'SteamDB', $_->{value}, sprintf('https://steamdb.info/app/%d/info/', $_->{value}) for $o->{_l}{steam}->@*;
        l 'dlsite';
        l 'gog';
        l 'itch';
        l 'patreonp';
        l 'patreon';
        l 'substar';
        l 'gamejolt';
        l 'denpa';
        l 'jlist';
        l 'jastusa';
        l 'fakku';
        l 'appstore';
        l 'googplay';
        l 'animateg';
        l 'freem';
        l 'freegame';
        l 'novelgam';
        l 'gyutto';
        l 'digiket';
        l 'melon';
        l 'melonjp';
        l 'mg';
        l 'nutaku';
        l 'getchu';
        l 'getchudl';
        l 'dmm';
        l 'toranoana';
        l 'booth';
        l 'playstation_jp';
        l 'playstation_na';
        l 'playstation_eu';
        l 'playstation_hk';
        l 'nintendo';
        l 'nintendo_jp';
        l 'nintendo_hk';
        c 'playasia', 'PlayAsia', $_->{url}, $_->{url}, undef, $_->{price} for $o->{_l}{_playasia}->@*;
    }

    for ($type eq 's' ? @obj : ()) {$o=$_;
        l 'website';
        w 'enwiki';
        w 'jawiki';
        l 'wikidata';
        l 'twitter';   w 'twitter'            if !$o->{_l}{twitter};
        l 'anidb';     w 'anidb_person'       if !$o->{_l}{anidb};
        l 'pixiv';     w 'pixiv_user'         if !$o->{_l}{pixiv};
        l 'mbrainz';   w 'musicbrainz_artist' if !$o->{_l}{mbrainz};
        l 'vgmdb';     w 'vgmdb_artist'       if !$o->{_l}{vgmdb};
        l 'discogs';   w 'discogs_artist'     if !$o->{_l}{discogs};
        l 'scloud';    w 'soundcloud'         if !$o->{_l}{scloud};
        l 'mobygames';
        l 'bgmtv';
        l 'imdb';
        l 'vndb';
        l 'egs_creator';
        l 'anison';
        l 'patreon';
        l 'substar';
        l 'kofi';
        l 'boosty';
        l 'youtube';
        l 'instagram';
        l 'deviantar';
        l 'facebook';
        l 'tumblr';
        l 'vk';
        l 'itch_dev';
    }

    for ($type eq 'p' ? @obj : ()) {$o=$_;
        l 'website';
        w 'enwiki';
        w 'jawiki';
        l 'wikidata';
        l 'twitter';          w 'twitter'            if !$o->{_l}{twitter};
        l 'pixiv';            w 'pixiv_user'         if !$o->{_l}{pixiv};
        l 'mobygames_comp';   w 'mobygames_company'  if !$o->{_l}{mobygames_comp};
        l 'gamefaqs_comp';    w 'gamefaqs_company'   if !$o->{_l}{gamefaqs_comp};
        l 'scloud';           w 'soundcloud'         if !$o->{_l}{scloud};
        l 'patreon';
        l 'substar';
        l 'boosty';
        l 'youtube';
        l 'instagram';
        l 'facebook';
        l 'vk';
        l 'itch_dev';
        c 'vnstat', 'VNStat', $o->{id} =~ s/^.//r, sprintf 'https://vnstat.net/developer/%d', $o->{id} =~ s/^.//r;
    }

    delete $_->{_l} for @obj;
}


# For use in VNWeb::HTML::revision_()
our $REVISION = [
    extlinks => 'External links',
    fmt => sub {
        my $l = $LINKS{$_->{site}};
        TUWF::func::txt_($l->{label}.': ');
        TUWF::func::a_(href => sprintf($l->{fmt}, $_->{value}), $_->{value});
    },
];


# For use in conjuction with the 'extlinks' validation. Converts the extlinks
# in $new to a format suitable for the entry's extlinks table.
# Sites without a regex can't be edited through the form and are thus copied
# over from $old.
sub normalize($old, $new) {
    $old->{extlinks} ||= [];
    $new->{extlinks} = [ grep $_->{site} eq 'website' || $LINKS{$_->{site}}{regex}, $new->{extlinks}->@* ];

    my %link2id = map +("$_->{site} $_->{value}", $_->{id}), $old->{extlinks}->@*;

    # Don't use INSERT .. ON CONFLICT here, that will increment the sequence even when the link already exists.
    $_->{link} = $link2id{"$_->{site} $_->{value}"} || $TUWF::OBJ->dbVali('
        WITH e(id) AS (
            SELECT id FROM extlinks WHERE site =', \$_->{site}, 'AND value =', \$_->{value}, '
        ), i(id) AS (
            INSERT INTO extlinks (site, value) SELECT', \$_->{site}, ',', \$_->{value}, 'WHERE NOT EXISTS(SELECT 1 FROM e) RETURNING id
        ) SELECT id FROM e UNION SELECT id FROM i
    ') for $new->{extlinks}->@*;

    push $new->{extlinks}->@*, grep !($_->{site} eq 'website' || $LINKS{$_->{site}}{regex}), $old->{extlinks}->@*;
}

1;
