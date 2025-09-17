package VNDB::ExtLinks;

use v5.36;
use VNDB::Config;
use VNDB::Schema;
use Exporter 'import';

our @EXPORT_OK = ('%LINKS', 'extlink_printf', 'enrich_vislinks', 'extlink_parse', 'extlink_split', 'extlink_fmt', 'extlink_form_pre', 'extlink_form_post');


# column name in wikidata table => \%info
# info keys:
#   property   Wikidata Property ID, used by the vntask fetcher
#   label      How the link is displayed on the website
#   fmt        How to generate the url (printf-style string or subroutine returning the full URL)
our %WIKIDATA = (
    enwiki             => { property => undef,   label => 'Wikipedia (en)', fmt => sub { sprintf 'https://en.wikipedia.org/wiki/%s', (shift =~ s/ /_/rg) =~ s/\?/%3f/rg } },
    jawiki             => { property => undef,   label => 'Wikipedia (ja)', fmt => sub { sprintf 'https://ja.wikipedia.org/wiki/%s', (shift =~ s/ /_/rg) =~ s/\?/%3f/rg } },
    website            => { property => 'P856',  label => undef,            fmt => undef },
    vndb               => { property => 'P3180', label => undef,            fmt => undef },
    mobygames          => { property => 'P1933', label => 'MobyGames',      fmt => 'https://www.mobygames.com/game/%s' },
    mobygames_company  => { property => 'P4773', label => 'MobyGames',      fmt => 'https://www.mobygames.com/company/%s' },
    gamefaqs_game      => { property => 'P4769', label => 'GameFAQs',       fmt => 'https://gamefaqs.gamespot.com/-/%s-' },
    gamefaqs_company   => { property => 'P6182', label => 'GameFAQs',       fmt => 'https://gamefaqs.gamespot.com/company/%s-' },
    anidb_anime        => { property => 'P5646', label => undef,            fmt => undef },
    anidb_person       => { property => 'P5649', label => 'AniDB',          fmt => 'https://anidb.net/cr%s' },
    ann_anime          => { property => 'P1985', label => undef,            fmt => undef },
    ann_manga          => { property => 'P1984', label => undef,            fmt => undef },
    musicbrainz_artist => { property => 'P434',  label => 'MusicBrainz',    fmt => 'https://musicbrainz.org/artist/%s' },
    twitter            => { property => 'P2002', label => 'Xitter',         fmt => 'https://x.com/%s' },
    vgmdb_product      => { property => 'P5659', label => 'VGMdb',          fmt => 'https://vgmdb.net/product/%s' },
    vgmdb_artist       => { property => 'P3435', label => 'VGMdb',          fmt => 'https://vgmdb.net/artist/%s' },
    discogs_artist     => { property => 'P1953', label => 'Discogs',        fmt => 'https://www.discogs.com/artist/%s' },
    acdb_char          => { property => 'P7013', label => undef,            fmt => undef },
    acdb_source        => { property => 'P7017', label => 'ACDB',           fmt => 'https://www.animecharactersdatabase.com/source.php?id=%s' },
    indiedb_game       => { property => 'P6717', label => 'IndieDB',        fmt => 'https://www.indiedb.com/games/%s' },
    howlongtobeat      => { property => 'P2816', label => 'HowLongToBeat',  fmt => 'http://howlongtobeat.com/game.php?id=%s' },
    crunchyroll        => { property => 'P4110', label => undef,            fmt => undef },
    igdb_game          => { property => 'P5794', label => 'IGDB',           fmt => 'https://www.igdb.com/games/%s' },
    giantbomb          => { property => 'P5247', label => undef,            fmt => undef },
    pcgamingwiki       => { property => 'P6337', label => 'PCGamingWiki',   fmt => 'https://www.pcgamingwiki.com/wiki/%s' },
    steam              => { property => 'P1733', label => undef,            fmt => undef },
    gog                => { property => 'P2725', label => 'GOG',            fmt => 'https://www.gog.com/game/%s' },
    pixiv_user         => { property => 'P5435', label => 'Pixiv',          fmt => 'https://www.pixiv.net/member.php?id=%d' },
    doujinshi_author   => { property => 'P7511', label => 'Doujinshi.org',  fmt => 'https://www.doujinshi.org/browse/author/%d/' },
    soundcloud         => { property => 'P3040', label => 'Soundcloud',     fmt => 'https://soundcloud.com/%s' },
    humblestore        => { property => 'P4477', label => undef,            fmt => undef },
    itchio             => { property => 'P7294', label => undef,            fmt => undef },
    playstation_jp     => { property => 'P5999', label => undef,            fmt => undef },
    playstation_na     => { property => 'P5944', label => undef,            fmt => undef },
    playstation_eu     => { property => 'P5971', label => undef,            fmt => undef },
    lutris             => { property => 'P7597', label => 'Lutris',         fmt => 'https://lutris.net/games/%s' },
    wine               => { property => 'P600',  label => 'Wine AppDB',     fmt => 'https://appdb.winehq.org/appview.php?iAppId=%d' },
);


# Captures a decimal integer, accepting but removing any leading zeros
my $int = qr/0*([1-9][0-9]*)/;

# extlink_site => \%info
# Site names are also exposed in the API and used for AdvSearch filters, so they should be stable.
# %info keys:
#   ent       Applicable DB entry types; String with id-prefixes, uppercase if multiple links are permitted for this site.
#   label     Name of the link
#   fmt       How to generate a url, can be:
#             - A printf-style string, where the 'value' is given as only argument
#             - A subroutine given three arguments: $value, $data, $affiliate
#               Should return a list of printf() arguments
#   parse     How to parse a url, can be:
#             - A regexp. Match is anchored on both sides, the first non-empty placeholder is extracted as 'value'.
#             - A subroutine given a URL, should return () or ($value, $data)
#             In both cases the URL to be matched has the ^https?:// prefix and the optional URL fragment removed.
#             (Only set for links that should be autodetected in the edit form)
#   patt      Human-readable URL pattern that corresponds to 'fmt' and 'parse'; Automatically derived from 'fmt' if not set.
#   affil     Whether these links should show up in the affiliate links box (when they have a known price).
our %LINKS = (
    afdian =>
        { ent   => 'sp'
        , label => 'Afdian'
        , fmt   => 'https://afdian.com/a/%s'
        , parse => qr{(?:www\.)?afdian\.com/(?:a/|@)([a-zA-Z0-9_]+)(?:[?/].*)?}
        },
    anidb =>
        { ent   => 's'
        , label => 'AniDB'
        , fmt   => 'https://anidb.net/cr%d'
        , parse => qr{anidb\.net/(?:cr|creator/)$int}
        },
    animateg =>
        { ent   => 'r'
        , label => 'Animate Games'
        , fmt   => 'https://www.animategames.jp/home/detail/%d'
        , parse => qr{(?:www\.)?animategames\.jp/home/detail/$int}
        },
    anison =>
        { ent   => 's'
        , label => 'Anison'
        , fmt   => 'http://anison.info/data/person/%d.html'
        , parse => qr{anison\.info/data/person/$int\.html}
        },
    appstore =>
        { ent   => 'r'
        , label => 'App Store'
        , fmt   => sub($v,$d,$a) {
            $d ? ('https://apps.apple.com/%s/app/id%d', $d, $v)
               : ('https://apps.apple.com/app/id%d', $v)
          },
        , parse => sub($u) {
            $u =~ qr{(?:itunes|apps)\.apple\.com/(?:([^/]+)/)?app/(?:[^/]+/)?id$int(?:[/\?].*)?} ? ($2, $1||'') : (),
          }
        },
    bgmtv =>
        { ent   => 's'
        , label => 'Bangumi'
        , fmt   => 'https://bgm.tv/person/%d'
        , parse => qr{(?:www\.)?(?:bgm|bangumi)\.tv/person/$int(?:[?/].*)?}
        },
    bilibili =>
        { ent   => 'sp'
        , label => 'Bilibili'
        , fmt   => 'https://space.bilibili.com/%d'
        , parse => qr{space.bilibili.com/$int(?:[\?/].*)?}
        },
    boosty =>
        { ent   => 'sp'
        , label => 'Boosty'
        , fmt   => 'https://boosty.to/%s'
        , parse => qr{boosty\.to/([a-z0-9_.-]+)/?}
        },
    booth =>
        { ent   => 'r'
        , label => 'BOOTH'
        , fmt   => 'https://booth.pm/en/items/%d'
        , parse => qr{(?:[a-z0-9_-]+\.)?booth\.pm/(?:[a-z-]+\/)?items/$int.*}
        , patt  => 'https://booth.pm/<language>/items/<id>  OR  https://<publisher>.booth.pm/items/<id>'
        },
    booth_pub =>
        { ent   => 'sp'
        , label => 'BOOTH'
        , fmt   => 'https://%s.booth.pm/'
        , parse => qr{([a-z0-9_-]+)\.booth\.pm/.*}
        },
    bsky =>
        { ent   => 'sp'
        , label => 'Bluesky'
        , fmt   => 'https://bsky.app/profile/%s'
        , parse => qr{(?:([a-z0-9-]+\.bsky\.social)|bsky\.app/profile/([a-z0-9\.-]+))/?}
        },
    cien =>
        { ent   => 'sp'
        , label => 'Ci-en'
        , fmt   => 'https://ci-en.dlsite.com/creator/%d'
          # Some creators are on the dlsite domain, others on ci-en.net. The
          # site always redirects to the correct domain. Let's use dlsite as
          # "main" here because that's where VN creators typically are.
        , parse => qr{(?:ci-en\.dlsite\.com|ci-en\.net)/creator/([0-9]+)}
        },
    denpa =>
        { ent   => 'r'
        , label => 'Denpasoft'
        , fmt   => sub($v,$d,$a) {
            $a &&= config->{denpa_affiliate};
            ('https://denpasoft.com/product/%s/'.($a||''), $v)
          }
        , parse => qr{(?:www\.)?denpasoft\.com/products?/([^/&#?:]+).*}
        , affil => !!config->{denpa_affiliate}
        },
    deviantar =>
        { ent   => 's'
        , label => 'DeviantArt'
        , fmt   => 'https://www.deviantart.com/%s'
        , parse => qr{(?:([a-z0-9-]+)\.deviantart\.com/?|(?:www\.)?deviantart\.com/([^/?]+)(?:[?/].*)?)}
        },
    digiket =>
        { ent   => 'r'
        , label => 'Digiket'
        , fmt   => 'https://www.digiket.com/work/show/_data/ID=ITM%07d/'
        , parse => qr{(?:www\.)?digiket\.com/.*ITM$int.*}
        },
    discogs =>
        { ent   => 's'
        , label => 'Discogs'
        , fmt   => 'https://www.discogs.com/artist/%d'
        , parse => qr{(?:www\.)?discogs\.com/artist/$int(?:[?/-].*)?}
        },
    dlsite =>
        { ent   => 'r'
        , label => 'DLsite',
        , fmt   => sub($v,$d,$a) {
            $a &&= config->{dlsite_affiliate};
            ('https://www.dlsite.com/%s/' . ($a ? "dlaf/=/link/work/aid/$a/id" : 'work/=/product_id') . '/%s.html', $d||'home', $v)
          }
        , parse => sub($u) {
            $u =~ qr{(?:www\.)?dlsite\.com/([^/]+)/(?:dlaf/=/link/work/aid/.*/id|work/=/product_id)/([VR]J[0-9]{6,8}).*} ? ($2,$1) : ()
          }
        , patt  => 'https://www.dlsite.com/<store>/work/=/product_id/<VJ or RJ-code>'
        , affil => !!config->{dlsite_affiliate}
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
          # TODO: Would be really nice to normalize this crap
        , parse => qr{((?:www\.|dlsoft\.)?dmm\.(?:com|co\.jp)/[^\s?]+)(?:\?.*)?}
        , patt  => 'https://<any link to dmm.com or dmm.co.jp>'
        },
    egs =>
        { ent   => 'r'
        , label => 'ErogameScape'
        , fmt   => 'https://erogamescape.dyndns.org/~ap2/ero/toukei_kaiseki/game.php?game=%d'
        , parse => qr{erogamescape\.dyndns\.org/~ap2/ero/toukei_kaiseki/(?:before_)?game\.php\?(?:.*&)?game=$int(?:&.*)?}
        },
    egs_creator =>
        { ent   => 's'
        , label => 'ErogameScape'
        , fmt   => 'https://erogamescape.dyndns.org/~ap2/ero/toukei_kaiseki/creater.php?creater=%d'
        , parse => qr{erogamescape\.dyndns\.org/~ap2/ero/toukei_kaiseki/(?:before_)?creater\.php\?(?:.*&)?creater=$int(?:&.*)?}
        },
    encubed => # Deprecated, site is long dead
        { ent   => 'v'
        , label => 'Novelnews'
        , fmt   => 'http://novelnews.net/tag/%s/'
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
        , parse => qr{(?:[^\.]+\.)?facebook\.com/(?:profile\.php\?id=([a-zA-Z0-9.-]+)(?:&.*)?|([a-zA-Z0-9.-]+)/?(?:\?.*)?)},
        },
    fakku =>
        { ent   => 'r'
        , label => 'Fakku'
        , fmt   => 'https://www.fakku.net/games/%s'
        , parse => qr{(?:www\.)?fakku\.(?:net|com)/games/([^/]+)(?:[/\?].*)?}
        },
    fanbox =>
        { ent   => 'sp'
        , label => 'Fanbox'
        , fmt   => 'https://%s.fanbox.cc/'
        , parse => qr{(?:www\.fanbox\.cc/@([a-z0-9-]+)|([a-z0-9-]+)\.fanbox\.cc/.*)}
        },
    fantia =>
        { ent   => 'sp'
        , label => 'Fantia'
        , fmt   => 'https://fantia.jp/fanclubs/%d'
        , parse => qr{fantia\.jp/fanclubs/$int(\?.*)?}
        },
    freegame =>
        { ent   => 'r'
        , label => 'Freegame Mugen'
        , fmt   => 'https://freegame-mugen.jp/%s.html'
          # TODO: Is the genre part of the identifier? Might want to split it out into 'data' if not.
        , parse => qr{(?:www\.)?freegame-mugen\.jp/([^/]+/game_[0-9]+)\.html}
        , patt  => 'https://freegame-mugen.jp/<genre>/game_<id>.html'
        },
    freem =>
        { ent   => 'r'
        , label => 'Freem!'
        , fmt   => 'https://www.freem.ne.jp/win/game/%d'
        , parse => qr{(?:www\.)?freem\.ne\.jp/win/game/$int}
        },
    gamefaqs_comp =>
        { ent   => 'p'
        , label => 'GameFAQs'
        , fmt   => 'https://gamefaqs.gamespot.com/company/%d-'
        , parse => qr{(?:www\.)?gamefaqs\.gamespot\.com/(?:games/)?company/$int-.*}
        },
    gamejolt =>
        { ent   => 'r'
        , label => 'Game Jolt'
        , fmt   => 'https://gamejolt.com/games/vn/%d', # /vn/ should be the game title, but it doesn't matter
        , parse => qr{(?:www\.)?gamejolt\.com/games/(?:[^/]+)/$int(?:/.*)?}
        },
    getchu =>
        { ent   => 'r'
        , label => 'Getchu'
        , fmt   => 'http://www.getchu.com/soft.phtml?id=%d'
        , parse => qr{(?:www\.)?getchu\.com/soft\.phtml\?id=$int.*}
        },
    getchudl =>
        { ent   => 'r'
        , label => 'DL.Getchu'
        , fmt   => 'http://dl.getchu.com/i/item%d'
        , parse => qr{(?:dl|order)\.getchu\.com/(?:i/item|(?:r|index).php.*[?&]gcd=D?)$int.*}
        },
    gog =>
        { ent   => 'r'
        , label => 'GOG',
        , fmt   => 'https://www.gog.com/game/%s'
        , parse => qr{(?:www\.)?gog\.com/(?:[a-z]{2}/)?game/([a-z0-9_]+).*}
        },
    googplay =>
        { ent   => 'r'
        , label => 'Google Play'
        , fmt   => 'https://play.google.com/store/apps/details?id=%s'
        , parse => qr{play\.google\.com/store/apps/details\?id=([^/&\?]+)(?:&.*)?}
        },
    gyutto =>
        { ent   => 'R'
        , label => 'Gyutto'
        , fmt   => 'https://gyutto.com/i/item%d'
        , parse => qr{(?:www\.)?gyutto\.(?:com|jp|me)/(?:.+\/)?i/item$int.*}
        },
    imdb =>
        { ent   => 's'
        , label => 'IMDb'
        , fmt   => 'https://www.imdb.com/name/nm%07d'
        , parse => qr{(?:www\.)?imdb\.com/name/nm$int(?:[?/].*)?}
        },
    instagram =>
        { ent   => 'sp'
        , label => 'Instagram'
        , fmt   => 'https://www.instagram.com/%s/'
        , parse => qr{(?:www\.)?instagram\.com/([^/?]+)(?:[?/].*)?}
        },
    itch =>
        { ent   => 'r'
        , label => 'Itch.io'
        , fmt   => 'https://%s'
        , parse => qr{([a-z0-9_-]+\.itch\.io/[a-z0-9_-]+)/?}
        , patt  => 'https://<artist>.itch.io/<product>'
        },
    itch_dev =>
        { ent   => 'sp'
        , label => 'Itch.io'
        , fmt   => 'https://%s.itch.io/'
        , parse => qr{(?:([a-z0-9_-]+)\.itch\.io/?|itch\.io/profile/([a-z0-9_-]+))}
        },
    jastusa =>
        { ent   => 'r'
        , label => 'JAST USA'
        , fmt   => sub($v,$d,$a) {
            $a &&= config->{jastusa_affiliate};
            ('https://jastusa.com/games/%s/%s'.($a ? "?via=$a" : ''), $v, $d||'vndb')
          }
        , parse => sub($u) { $u =~ qr{(?:www\.)?jastusa\.com/games/([a-z0-9_-]+)/([^/]+)} }
        , patt  => 'https://jastusa.com/games/<code>/<title>'
        , affil => !!config->{jastusa_affiliate}
        },
    jlist =>
        { ent   => 'r'
        , label => 'J-List'
        , fmt   => sub($v,$d,$a) {
            $a &&= config->{jlist_affiliate};
            ('https://'.($a ? "a.jlist.com/moe.php?acc=$a&pg=" : 'jlist.com').'/shop/product/%s', $v)
          }
        , parse => qr{(?:www\.)?(?:jlist|jbox)\.com/shop/product/([^/#?]+).*}
        , affil => !!config->{jlist_affiliate}
        },
    johren =>
        { ent   => 'R'
        , label => 'Johren'
        , fmt   => 'https://www.johren.games/games/download/%s/'
        , parse => qr{www\.johren\.(?:net|games)/games/download/([^/#?]+).*}
        },
    kagura =>
        { ent   => 'r'
        , label => 'Kagura Games'
        , fmt   => 'https://www.kaguragames.com/product/%s/'
        , parse => qr{(?:www\.)?kaguragame(?:r|s|sjp)\.com/(?:product/)?([^/#?]+).*}
        },
    kofi =>
        { ent   => 's'
        , label => 'Ko-fi'
        , fmt   => 'https://ko-fi.com/%s'
        , parse => qr{(?:www\.)?ko-fi\.com/([^/?]+)(?:[?/].*)?}
        },
    mbrainz =>
        { ent   => 's'
        , label => 'MusicBrainz'
        , fmt   => 'https://musicbrainz.org/artist/%s'
        , parse => qr{musicbrainz\.org/artist/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})}
        },
    melon =>
        { ent   => 'r'
        , label => 'Melonbooks.com'
        , fmt   => 'https://www.melonbooks.com/index.php?main_page=product_info&products_id=IT%010d'
        , parse => qr{(?:www\.)?melonbooks\.com/.*products_id=IT$int.*}
        },
    melonjp =>
        { ent   => 'r'
        , label => 'Melonbooks.co.jp'
        , fmt   => 'https://www.melonbooks.co.jp/detail/detail.php?product_id=%d',
        , parse => qr{(?:www\.)?melonbooks\.co\.jp/detail/detail\.php\?product_id=$int(&:?.*)?}
        },
    mg =>
        { ent   => 'r'
        , label => 'MangaGamer'
        , fmt   => sub($v,$d,$a) {
            $a &&= config->{mg_affiliate};
            ('https://www.mangagamer.com'.($d?'':'/r18').'/detail.php?product_code=%d'.($a?"&af=$a":''), $v)
          }
        , parse => qr{(?:www\.)?mangagamer\.com/.*product_code=$int.*}
        , affil => !!config->{mg_affiliate}
        },
    mobygames =>
        { ent   => 'sp'
        , label => 'MobyGames'
        , fmt   => 'https://www.mobygames.com/person/%d'
        , parse => qr{(?:www\.)?mobygames\.com/person/$int(?:[?/].*)?}
        },
    mobygames_comp =>
        { ent   => 'sp'
        , label => 'MobyGames'
        , fmt   => 'https://www.mobygames.com/company/%d'
        , parse => qr{(?:www\.)?mobygames\.com/company/$int(?:[?/].*)?}
        },
    nijie =>
        { ent   => 'sp'
        , label => 'Nijie'
        , fmt   => 'https://nijie.info/members.php?id=%d'
        , parse => qr{nijie\.info/members(?:_illust)?\.php\?id=$int}
        },
    nintendo =>
        { ent   => 'r'
        , label => 'Nintendo'
        , fmt   => 'https://www.nintendo.com/store/products/%s/'
        , parse => qr{www\.nintendo\.com\/store\/products\/([-a-z0-9]+)\/}
        },
    nintendo_hk =>
        { ent   => 'r'
        , label => 'Nintendo (HK)'
        , fmt   => 'https://store.nintendo.com.hk/%d'
        , parse => qr{store\.nintendo\.com\.hk/$int}
        },
    nintendo_jp =>
        { ent   => 'r'
        , label => 'Nintendo (JP)'
        , fmt   => 'https://store-jp.nintendo.com/item/software/D%d'
        , parse => qr{store-jp\.nintendo\.com/(?:item|list)/software/D?$int(?:\.html)?}
        },
    novelgam =>
        { ent   => 'r'
        , label => 'NovelGame'
        , fmt   => 'https://novelgame.jp/games/show/%d'
        , parse => qr{(?:www\.)?novelgame\.jp/games/show/$int}
        },
    nutaku =>
        { ent   => 'r'
        , label => 'Nutaku'
        , fmt   => 'https://www.nutaku.net/games/%s/'
        # The section part does sometimes link to different pages, but it's the same game and the non-section link always works.
        , parse => qr{(?:www\.)?nutaku\.net/games/(?:mobile/|download/|app/)?([a-z0-9-]+)/?}
        },
    patreon =>
        { ent   => 'rsp'
        , label => 'Patreon'
        , fmt   => 'https://www.patreon.com/%s'
        , parse => qr{(?:www\.)?patreon\.com/(?:c/)?(?!user[\?/]|posts[\?/]|join[\?/])([^/?]+).*}
        },
    patreonp =>
        { ent   => 'r'
        , label => 'Patreon post'
        , fmt   => 'https://www.patreon.com/posts/%d'
        , parse => qr{(?:www\.)?patreon\.com/posts/(?:[^/?]+-)?$int.*}
        },
    pixiv =>
        { ent   => 'sp'
        , label => 'Pixiv'
        , fmt   => 'https://www.pixiv.net/member.php?id=%d'
        , parse => qr{www\.pixiv\.net/(?:member\.php\?id=|en/users/|users/)$int}
        },
    playasia =>
        { ent   => 'R'
        , label => 'PlayAsia'
        , fmt   => sub($v,$d,$a) {
            $a &&= config->{playasia_tagid};
            $a = $a ? "?tagid=$a" : '';
            length $d ? ("https://www.play-asia.com/%s/13/70%s$a", $d, $v)
                      : ("https://www.play-asia.com/13/70%s$a", $v)
          }
        , parse => sub($u) {
            $u =~ qr{www\.play-asia\.com/(?:([^/]+)/)?13/70([1-9a-z][0-9a-z]+)(?:[?#/].*)?} ? ($2, $1//'') : ()
          }
        , patt  => 'https://www.play-asia.com/<title>/13/<code>'
        , affil => !!config->{playasia_tagid}
        },
    playstation_eu =>
        { ent   => 'r'
        , label => 'PlayStation Store (EU)'
        , fmt   => 'https://store.playstation.com/en-gb/product/%s'
        , parse => qr{store\.playstation\.com/(?:[-a-z]+\/)?product\/(EP\d{4}-[A-Z]{4}\d{5}_00-[\dA-Z_]{16})}
        },
    playstation_hk =>
        { ent   => 'r'
        , label => 'PlayStation Store (HK)'
        , fmt => 'https://store.playstation.com/en-hk/product/%s'
        , parse => qr{store\.playstation\.com/(?:[-a-z]+\/)?product\/(HP\d{4}-[A-Z]{4}\d{5}_00-[\dA-Z_]{16})}
        },
    playstation_jp =>
        { ent   => 'r'
        , label => 'PlayStation Store (JP)'
        , fmt => 'https://store.playstation.com/ja-jp/product/%s'
        , parse => qr{store\.playstation\.com/(?:[-a-z]+\/)?product\/(JP\d{4}-[A-Z]{4}\d{5}_00-[\dA-Z_]{16})}
        },
    playstation_na =>
        { ent   => 'r'
        , label => 'PlayStation Store (NA)'
        , fmt => 'https://store.playstation.com/en-us/product/%s'
        , parse => qr{store\.playstation\.com/(?:[-a-z]+\/)?product\/(UP\d{4}-[A-Z]{4}\d{5}_00-[\dA-Z_]{16})}
        },
    renai =>
        { ent   => 'v'
        , label => 'Renai.us'
        , fmt   => 'https://renai.us/game/%s'
        , parse => qr{renai\.us/game/([^/]+)}
        },
    scloud =>
        { ent   => 'sp'
        , label => 'SoundCloud'
        , fmt   => 'https://soundcloud.com/%s'
        , parse => qr{soundcloud\.com/([a-z0-9_-]+)}
        },
    steam =>
        { ent   => 'r'
        , label => 'Steam'
        , fmt   => 'https://store.steampowered.com/app/%d/'
        , parse => qr{(?:www\.)?(?:store\.steampowered\.com/app/$int(?:/.*)?|steamcommunity\.com/(?:app|games)/$int(?:/.*)?|steamdb\.info/app/$int(?:/.*)?)}
        },
    steam_curator =>
        { ent   => 'sp'
        , label => 'Steam Curator'
        , fmt   => 'https://store.steampowered.com/curator/%d'
        , parse => qr{store\.steampowered\.com/curator/$int(?:[-/].*)?}
        },
    substar =>
        { ent   => 'rsp'
        , label => 'SubscribeStar'
        , fmt   => 'https://subscribestar.%s'
        , parse => qr{(?:www\.)?subscribestar\.((?:adult|com)/[^/?]+).*}
        , patt  => 'https://subscribestar.<adult or com>/<name>'
        },
    toranoana =>
        { ent   => 'r'
        , label => 'Toranoana'
        # ec.* is for 18+, ecs.toranoana.jp is for non-18+.
        # ec.toranoana.shop will redirect to ecs.* as appropriate for the product ID, but ec.toranoana.jp won't.
        , fmt   => 'https://ec.toranoana.shop/tora/ec/item/%012d/'
        , parse => qr{(?:www\.)?ecs?\.toranoana\.(?:shop|jp)/(?:aqua/ec|(?:tora|joshi)(?:/ec|_r/ec|_d/digi|_rd/digi)?)/item/$int.*}
        , patt  => 'https://ec.toranoana.<shop or jp>/<shop>/item/<number>/'
        },
    tumblr =>
        { ent   => 'sp'
        , label => 'Tumblr'
        , fmt   => 'https://%s.tumblr.com/'
        , parse => qr{(?:(?:www\.)?tumblr\.com/(?:blog\/)?([a-z0-9-]+)|([a-z0-9-]+)\.tumblr\.com)(?:/.*)?}
        },
    twitter =>
        { ent   => 'SP',
        , label => 'Xitter'
        , fmt   => 'https://x.com/%s'
        , parse => qr{(?:(?:www\.)?(?:x|twitter)\.com|nitter\.[^/]+)/([^?\/ ]{1,16})(?:[?/].*)?}
        },
    vgmdb =>
        { ent   => 's'
        , label => 'VGMdb'
        , fmt   => 'https://vgmdb.net/artist/%d'
        , parse => qr{vgmdb\.net/artist/$int}
        },
    vgmdb_org =>
        { ent   => 's'
        , label => 'VGMdb org'
        , fmt   => 'https://vgmdb.net/org/%d'
        , parse => qr{vgmdb\.net/org/$int}
        },
    vk =>
        { ent   => 'sp'
        , label => 'VK'
        , fmt   => 'https://vk.com/%s'
        , parse => qr{vk\.com/([a-zA-Z0-9_.]+)}
        },
    vndb =>
        { ent   => 's'
        , label => 'VNDB user'
        , fmt   => 'https://vndb.org/%s'
        , parse => qr{vndb\.org/(u[1-9][0-9]*)}
        },
    website => # Official website, catch-all
        { ent   => 'rsp'
        , label => 'Official website'
        , fmt   => '%s'
        },
    weibo =>
        { ent   => 'sp'
        , label => 'Weibo'
        , fmt   => 'https://weibo.com/u/%d'
        , parse => qr{(?:www\.)?weibo\.com/u/$int}
        },
    wikidata =>
        { ent   => 'vsp'
        , label => 'Wikidata'
        , fmt   => 'https://www.wikidata.org/wiki/Q%d'
        , parse => qr{(?:www\.)?wikidata\.org/wiki/(?:Special:EntityPage/)?Q$int}
        },
    wp => # Deprecated, replaced with wikidata
        { ent   => 'vsp'
        , label => 'Wikipedia'
        , fmt   => 'https://en.wikipedia.org/wiki/%s'
        },
    youtube =>
        { ent   => 'sp'
        , label => 'Youtube'
        # There's also /user/<name> syntax, but <name> may be different in this form *sigh*.
        , fmt   => 'https://www.youtube.com/@%s'
        , parse => qr{(?:www\.)?youtube\.com/@([^/?]+)}
        },
);


# Returns (site, value, data) or ()
sub extlink_parse($url) {
    return () if $url !~ s{^https?://}{};
    $url =~ s/#.*$//;
    for my ($site, $lnk) (%LINKS) {
        if (ref $lnk->{parse} eq 'CODE') {
            my ($v, $d) = $lnk->{parse}->($url);
            return ($site, $v, $d) if defined $v;
        } elsif ($lnk->{parse}) {
            return ($site, (grep defined, @{^CAPTURE})[0], '') if $url =~ qr/^$lnk->{parse}$/;
        }
    }
    return ();
}


sub extlink_printf($site, $value, $data='', $affiliate=0) {
    my $lnk = $LINKS{$site} or return;
    ref $lnk->{fmt} ? $lnk->{fmt}->($value, $data, $affiliate) : ($lnk->{fmt}, $value);
}

sub extlink_fmt {
    my($fmt, @a) = extlink_printf @_;
    sprintf $fmt, @a;
}


sub extlink_split {
    my($fmt, @a) = extlink_printf @_;
    [ map /^%/ ? sprintf $_, shift @a : $_, split /(%[-0-9\.]*[sd])/, $fmt ]
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
    for my $s (@ids_ne ? FU::fu->SQL('
        SELECT e.id, l.site, l.value, l.data, l.price
          FROM', FU::SQL::RAW({qw/r releases_extlinks  s staff_extlinks  p producers_extlinks  v vn_extlinks/}->{$type}), 'e
          JOIN extlinks l ON l.id = e.link
         WHERE e.id', FU::SQL::IN(\@ids_ne)
    )->allh->@* : ()) {
        push $ids{$s->{id}}{_l}{$s->{site}}->@*, $s;
        push @w_ids, $s->{value} if $s->{site} eq 'wikidata';
    }

    my $w = @w_ids ? FU::fu->SQL('SELECT id, * FROM wikidata WHERE id', FU::SQL::IN(\@w_ids))->kvh : {};

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
        c $f, $l->{label}, $_->{value},
            extlink_fmt($f, $_->{value}, $_->{data}),
            extlink_fmt($f, $_->{value}, $_->{data}, 1),
            $_->{price} for $o->{_l}{$f} ? $o->{_l}{$f}->@* : ();
    }
    my sub w($f) {
        return if !$o->{_l}{wikidata};
        my $v = $w->{ $o->{_l}{wikidata}[0]{value} }{$f};
        my $l = $WIKIDATA{$f};
        c $f, $l->{label}, $_, ref $l->{fmt} ? $l->{fmt}->($_) : sprintf($l->{fmt}, $_)
            for ref $v ? @$v : $v ? $v : ();
    }

    for ($type eq 'v' ? @obj : ()) {$o=$_;
        w 'enwiki';
        w 'jawiki';
        l 'wikidata';
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
        l 'renai';
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
        l 'jastusa';
        l 'jlist';
        l 'johren';
        l 'kagura';
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
        l 'playasia';
        l 'playstation_jp';
        l 'playstation_na';
        l 'playstation_eu';
        l 'playstation_hk';
        l 'nintendo';
        l 'nintendo_jp';
        l 'nintendo_hk';
    }

    for ($type eq 's' ? @obj : ()) {$o=$_;
        l 'website';
        w 'enwiki';
        w 'jawiki';
        l 'wikidata';
        l 'bsky';
        l 'twitter';   w 'twitter'            if !$o->{_l}{twitter};
        l 'anidb';     w 'anidb_person'       if !$o->{_l}{anidb};
        l 'pixiv';     w 'pixiv_user'         if !$o->{_l}{pixiv};
        l 'mbrainz';   w 'musicbrainz_artist' if !$o->{_l}{mbrainz};
        l 'vgmdb';     w 'vgmdb_artist'       if !$o->{_l}{vgmdb};
        l 'vgmdb_org';
        l 'discogs';   w 'discogs_artist'     if !$o->{_l}{discogs};
        l 'scloud';    w 'soundcloud'         if !$o->{_l}{scloud};
        l 'mobygames';
        l 'mobygames_comp';
        l 'bgmtv';
        l 'bilibili';
        l 'weibo';
        l 'imdb';
        l 'vndb';
        l 'egs_creator';
        l 'anison';
        l 'afdian';
        l 'patreon';
        l 'substar';
        l 'kofi';
        l 'boosty';
        l 'cien';
        l 'booth_pub';
        l 'fantia';
        l 'nijie';
        l 'youtube';
        l 'instagram';
        l 'deviantar';
        l 'facebook';
        l 'fanbox';
        l 'tumblr';
        l 'vk';
        l 'itch_dev';
        l 'steam_curator';
    }

    for ($type eq 'p' ? @obj : ()) {$o=$_;
        l 'website';
        w 'enwiki';
        w 'jawiki';
        l 'wikidata';
        l 'bsky';
        l 'twitter';          w 'twitter'            if !$o->{_l}{twitter};
        l 'pixiv';            w 'pixiv_user'         if !$o->{_l}{pixiv};
        l 'mobygames_comp';   w 'mobygames_company'  if !$o->{_l}{mobygames_comp};
        l 'mobygames';
        l 'gamefaqs_comp';    w 'gamefaqs_company'   if !$o->{_l}{gamefaqs_comp};
        l 'scloud';           w 'soundcloud'         if !$o->{_l}{scloud};
        l 'afdian';
        l 'patreon';
        l 'substar';
        l 'boosty';
        l 'cien';
        l 'fantia';
        l 'nijie';
        l 'booth_pub';
        l 'bilibili';
        l 'weibo';
        l 'youtube';
        l 'instagram';
        l 'facebook';
        l 'fanbox';
        l 'tumblr';
        l 'vk';
        l 'itch_dev';
        l 'steam_curator';
    }

    delete $_->{_l} for @obj;
}


# For use in VNWeb::HTML::revision_()
our $REVISION = [
    extlinks => 'External links',
    fmt => sub {
        my $l = $LINKS{$_->{site}};
        FU::XMLWriter::txt_($l->{label}.': ');
        FU::XMLWriter::a_(href => extlink_fmt($_->{site}, $_->{value}, $_->{data}), $_->{value});
    },
];


sub extlink_form_pre($e) {
    $_->{split} = extlink_split @{$_}{qw/site value data/} for $e->{extlinks}->@*;
}


# For use in conjuction with the 'extlinks' validation. Converts the extlinks
# in $new to a format suitable for the entry's extlinks table.
# Sites without a 'parse' can't be edited through the form and are thus copied
# over from $old.
sub extlink_form_post($old, $new) {
    $old->{extlinks} ||= [];
    $new->{extlinks} = [ grep $_->{site} eq 'website' || $LINKS{$_->{site}}{parse}, $new->{extlinks}->@* ];

    my %link2id = map +("$_->{site} $_->{value}", $_->{id}), $old->{extlinks}->@*;

    # Don't use INSERT .. ON CONFLICT here, that will increment the sequence even when the link already exists.
    # Update the data column only if we haven't fetched the link.
    $_->{link} = $link2id{"$_->{site} $_->{value}"} || FU::fu->sql('
        WITH e(id) AS (
            SELECT id FROM extlinks WHERE site = $1 AND value = $2
        ), i(id) AS (
            INSERT INTO extlinks (site, value, data) SELECT $1, $2, $3 WHERE NOT EXISTS(SELECT 1 FROM e) RETURNING id
        ), u AS (
            UPDATE extlinks SET data = $3 FROM e WHERE e.id = extlinks.id AND extlinks.lastfetch IS NULL AND extlinks.data IS DISTINCT FROM $3
        ) SELECT id FROM e UNION SELECT id FROM i
    ', @{$_}{qw/site value data/})->val for $new->{extlinks}->@*;

    push $new->{extlinks}->@*, grep !($_->{site} eq 'website' || $LINKS{$_->{site}}{parse}), $old->{extlinks}->@*;
}

1;
