package VNDB::ExtLinks;

use v5.26;
use warnings;
use VNDB::Config;
use VNDB::Schema;
use Exporter 'import';

our @EXPORT = qw/
    sql_extlinks
    enrich_extlinks
    revision_extlinks
    validate_extlinks
/;


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
    twitter            => { type => 'text[]',     property => 'P2002', label => 'Twitter',        fmt => 'https://twitter.com/%s' },
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


# dbentry_type => column name => \%info
# Column names are also used for AdvSearch filters, so they should be stable.
# info keys:
#   label     Name of the link
#   fmt       How to generate a url (basic version, printf-style only)
#   fmt2      How to generate a better url
#             (printf-style string or subroutine, given a hashref of the DB entry and returning a new 'fmt' string)
#             ("better" meaning proper store section, affiliate link)
#   regex     Regex to detect a URL and extract the database value (the first non-empty placeholder).
#             Excludes a leading qr{^https?://} match and is anchored on both sites, see full_regex() below.
#             (A valid DB value must survive a 'fmt' -> 'regex' round trip)
#             (Only set for links that should be autodetected in the edit form)
#   patt      Human-readable URL pattern that corresponds to 'fmt' and 'regex'; Automatically derived from 'fmt' if not set.
our %LINKS = (
    v => {
        l_renai    => { label => 'Renai.us',         fmt => 'https://renai.us/game/%s' },
        l_wikidata => { label => 'Wikidata',         fmt => 'https://www.wikidata.org/wiki/Q%d' },
        # deprecated
        l_wp       => { label => 'Wikipedia',        fmt => 'https://en.wikipedia.org/wiki/%s' },
        l_encubed  => { label => 'Novelnews',        fmt => 'http://novelnews.net/tag/%s/' },
    },
    r => {
        website    => { label => 'Official website', fmt => '%s' },
        l_egs      => { label => 'ErogameScape'
                      , fmt   => 'https://erogamescape.dyndns.org/~ap2/ero/toukei_kaiseki/game.php?game=%d'
                      , regex => qr{erogamescape\.dyndns\.org/~ap2/ero/toukei_kaiseki/(?:before_)?game\.php\?(?:.*&)?game=([0-9]+)(?:&.*)?} },
        l_steam    => { label => 'Steam'
                      , fmt   => 'https://store.steampowered.com/app/%d/'
                      , fmt2  => 'https://store.steampowered.com/app/%d/?utm_source=vndb'
                      , regex => qr{(?:www\.)?(?:store\.steampowered\.com/app/([0-9]+)(?:/.*)?|steamcommunity\.com/(?:app|games)/([0-9]+)(?:/.*)?|steamdb\.info/app/([0-9]+)(?:/.*)?)} },
        l_dlsite   => { label => 'DLsite'
                      , fmt   => 'https://www.dlsite.com/home/work/=/product_id/%s.html'
                      , fmt2  => sub { config->{dlsite_url} && sprintf config->{dlsite_url}, shift->{l_dlsite_shop}||'home' }
                      , regex => qr{(?:www\.)?dlsite\.com/.*/(?:dlaf/=/link/work/aid/.*/id|work/=/product_id)/([VR]J[0-9]{6,8}).*}
                      , patt  => 'https://www.dlsite.com/<store>/work/=/product_id/<VJ or RJ-code>' },
        l_gog      => { label => 'GOG'
                      , fmt   => 'https://www.gog.com/game/%s'
                      , regex => qr{(?:www\.)?gog\.com/(?:[a-z]{2}/)?game/([a-z0-9_]+).*} },
        l_itch     => { label => 'Itch.io'
                      , fmt   => 'https://%s'
                      , regex => qr{([a-z0-9_-]+\.itch\.io/[a-z0-9_-]+)}
                      , patt  => 'https://<artist>.itch.io/<product>' },
        l_patreonp => { label => 'Patreon post'
                      , fmt   => 'https://www.patreon.com/posts/%d'
                      , regex => qr{(?:www\.)?patreon\.com/posts/(?:[^/?]+-)?([0-9]+).*} },
        l_patreon  => { label => 'Patreon'
                      , fmt   => 'https://www.patreon.com/%s'
                      , regex => qr{(?:www\.)?patreon\.com/(?!user[\?/]|posts[\?/]|join[\?/])([^/?]+).*} },
        l_substar  => { label => 'SubscribeStar'
                      , fmt   => 'https://subscribestar.%s'
                      , regex => qr{(?:www\.)?subscribestar\.((?:adult|com)/[^/?]+).*}
                      , patt  => 'https://subscribestar.<adult or com>/<name>' },
        l_denpa    => { label => 'Denpasoft'
                      , fmt   => 'https://denpasoft.com/product/%s/'
                      , fmt2  => config->{denpa_url}
                      , regex => qr{(?:www\.)?denpasoft\.com/products?/([^/&#?:]+).*} },
        l_jlist    => { label => 'J-List'
                      , fmt   => 'https://www.jlist.com/shop/product/%s'
                      , fmt2  => config->{jlist_url},
                      , regex => qr{(?:www\.)?(?:jlist|jbox)\.com/shop/product/([^/#?]+).*} },
        l_jastusa  => { label => 'JAST USA'
                      , fmt   => 'https://jastusa.com/games/%s/vndb'
                      , fmt2  => sub { config->{jastusa_url} && sprintf config->{jastusa_url}, shift->{l_jast_slug}||'vndb' },
                      , regex => qr{(?:www\.)?jastusa\.com/games/([a-z0-9_-]+)/[^/]+}
                      , patt  => 'https://jastusa.com/games/<code>/<title>' },
        l_fakku    => { label => 'Fakku'
                      , fmt   => 'https://www.fakku.net/games/%s'
                      , regex => qr{(?:www\.)?fakku\.(?:net|com)/games/([^/]+)(?:[/\?].*)?} },
        l_googplay => { label => 'Google Play'
                      , fmt   => 'https://play.google.com/store/apps/details?id=%s'
                      , regex => qr{play\.google\.com/store/apps/details\?id=([^/&\?]+)(?:&.*)?} },
        l_appstore => { label => 'App Store'
                      , fmt   => 'https://apps.apple.com/app/id%d'
                      , regex => qr{(?:itunes|apps)\.apple\.com/(?:[^/]+/)?app/(?:[^/]+/)?id([0-9]+)([/\?].*)?} },
        l_animateg => { label => 'Animate Games'
                      , fmt   => 'https://www.animategames.jp/home/detail/%d'
                      , regex => qr{(?:www\.)?animategames\.jp/home/detail/([0-9]+)} },
        l_freem    => { label => 'Freem!'
                      , fmt   => 'https://www.freem.ne.jp/win/game/%d'
                      , regex => qr{(?:www\.)?freem\.ne\.jp/win/game/([0-9]+)} },
        l_freegame => { label => 'Freegame Mugen'
                      , fmt   => 'https://freegame-mugen.jp/%s.html'
                      , regex => qr{(?:www\.)?freegame-mugen\.jp/([^/]+/game_[0-9]+)\.html}
                      , patt  => 'https://freegame-mugen.jp/<genre>/game_<id>.html' },
        l_novelgam => { label => 'NovelGame'
                      , fmt   => 'https://novelgame.jp/games/show/%d'
                      , regex => qr{(?:www\.)?novelgame\.jp/games/show/([0-9]+)} },
        l_gyutto   => { label => 'Gyutto'
                      , fmt   => 'https://gyutto.com/i/item%d'
                      , regex => qr{(?:www\.)?gyutto\.(?:com|jp|me)/(?:.+\/)?i/item([0-9]+).*} },
        l_digiket  => { label => 'Digiket'
                      , fmt   => 'https://www.digiket.com/work/show/_data/ID=ITM%07d/'
                      , regex => qr{(?:www\.)?digiket\.com/.*ITM([0-9]{7}).*} },
        l_melon    => { label => 'Melonbooks.com'
                      , fmt   => 'https://www.melonbooks.com/index.php?main_page=product_info&products_id=IT%010d'
                      , regex => qr{(?:www\.)?melonbooks\.com/.*products_id=IT([0-9]{10}).*} },
        l_melonjp  => { label => 'Melonbooks.co.jp'
                      , fmt   => 'https://www.melonbooks.co.jp/detail/detail.php?product_id=%d',
                      , regex => qr{(?:www\.)?melonbooks\.co\.jp/detail/detail\.php\?product_id=([0-9]+)(&:?.*)?} },
        l_mg       => { label => 'MangaGamer'
                      , fmt   => 'https://www.mangagamer.com/r18/detail.php?product_code=%d'
                      , fmt2  => sub { config->{ !defined($_[0]{l_mg_r18}) || $_[0]{l_mg_r18} ? 'mg_r18_url' : 'mg_main_url' } }
                      , regex => qr{(?:www\.)?mangagamer\.com/.*product_code=([0-9]+).*} },
        l_getchu   => { label => 'Getchu'
                      , fmt   => 'http://www.getchu.com/soft.phtml?id=%d'
                      , regex => qr{(?:www\.)?getchu\.com/soft\.phtml\?id=([0-9]+).*} },
        l_getchudl => { label => 'DL.Getchu'
                      , fmt   => 'http://dl.getchu.com/i/item%d'
                      , regex => qr{(?:dl|order)\.getchu\.com/(?:i/item|(?:r|index).php.*[?&]gcd=D?0*)([0-9]+).*} },
        l_dmm      => { label => 'DMM'
                      , fmt   => 'https://%s'
                      , regex => qr{((?:www\.|dlsoft\.)?dmm\.(?:com|co\.jp)/[^\s?]+)(?:\?.*)?}
                      , patt  => 'https://<any link to dmm.com or dmm.co.jp>' },
        l_toranoana=> { label => 'Toranoana'
                        # ec.* is for 18+, ecs.toranoana.jp is for non-18+.
                        # ec.toranoana.shop will redirect to ecs.* as appropriate for the product ID, but ec.toranoana.jp won't.
                      , fmt   => 'https://ec.toranoana.shop/tora/ec/item/%012d/'
                      , regex => qr{(?:www\.)?ecs?\.toranoana\.(?:shop|jp)/(?:aqua/ec|(?:tora|joshi)(?:/ec|_r/ec|_d/digi|_rd/digi)?)/item/([0-9]{12}).*}
                      , patt  => 'https://ec.toranoana.<shop or jp>/<shop>/item/<number>/' },
        l_booth    => { label => 'BOOTH'
                      , fmt   => 'https://booth.pm/en/items/%d'
                      , regex => qw{(?:[a-z0-9_-]+\.)?booth\.pm/(?:[a-z-]+\/)?items/([0-9]+).*}
                      , patt  => 'https://booth.pm/<language>/items/<id>  OR  https://<publisher>.booth.pm/items/<id>' },
        l_gamejolt => { label => 'Game Jolt'
                      , fmt   => 'https://gamejolt.com/games/vn/%d', # /vn/ should be the game title, but it doesn't matter
                      , regex => qr{(?:www\.)?gamejolt\.com/games/(?:[^/]+)/([0-9]+)(?:/.*)?} },
        l_nutaku   => { label => 'Nutaku'
                      , fmt   => 'https://www.nutaku.net/games/%s/'
                      , regex => qr{(?:www\.)?nutaku\.net/games/(?:mobile/|download/|app/)?([a-z0-9-]+)/?} }, # The section part does sometimes link to different pages, but it's the same game and the non-section link always works.
        l_playstation_jp => { label => 'PlayStation Store (JP)'
                            , fmt => 'https://store.playstation.com/ja-jp/product/%s'
                            , regex => qr{store\.playstation\.com/(?:[-a-z]+\/)?product\/(JP\d{4}-[A-Z]{4}\d{5}_00-[\dA-Z_]{16})} },
        l_playstation_na => { label => 'PlayStation Store (NA)'
                            , fmt => 'https://store.playstation.com/en-us/product/%s'
                            , regex => qr{store\.playstation\.com/(?:[-a-z]+\/)?product\/(UP\d{4}-[A-Z]{4}\d{5}_00-[\dA-Z_]{16})} },
        l_playstation_eu => { label => 'PlayStation Store (EU)'
                            , fmt => 'https://store.playstation.com/en-gb/product/%s'
                            , regex => qr{store\.playstation\.com/(?:[-a-z]+\/)?product\/(EP\d{4}-[A-Z]{4}\d{5}_00-[\dA-Z_]{16})} },
        l_playstation_hk => { label => 'PlayStation Store (HK)'
                            , fmt => 'https://store.playstation.com/en-hk/product/%s'
                            , regex => qr{store\.playstation\.com/(?:[-a-z]+\/)?product\/(HP\d{4}-[A-Z]{4}\d{5}_00-[\dA-Z_]{16})} },
        l_nintendo     => { label => 'Nintendo'
                          , fmt   => 'https://www.nintendo.com/store/products/%s/'
                          , regex => qr{www\.nintendo\.com\/store\/products\/([-a-z0-9]+-(?:switch|wii-u|3ds))\/} },
        l_nintendo_jp  => { label => 'Nintendo (JP)'
                          , fmt   => 'https://store-jp.nintendo.com/list/software/%d.html'
                          , regex => qr{store-jp\.nintendo\.com/list/software/([0-9]+).html} },
        l_nintendo_hk  => { label => 'Nintendo (HK)'
                          , fmt   => 'https://store.nintendo.com.hk/%d'
                          , regex => qr{store\.nintendo\.com\.hk/([0-9]+)} },
        # deprecated
        l_dlsiteen => { label => 'DLsite (eng)', fmt => 'https://www.dlsite.com/eng/work/=/product_id/%s.html' },
        l_erotrail => { label => 'ErogeTrailers', fmt => 'http://erogetrailers.com/soft/%d' },
    },
    s => {
        l_site     => { label => 'Official website', fmt => '%s' },
        l_wikidata => { label => 'Wikidata'
                      , fmt   => 'https://www.wikidata.org/wiki/Q%d'
                      , regex => qr{www\.wikidata\.org/wiki/Q([1-9][0-9]*)} },
        l_twitter  => { label => 'Xitter'
                      , fmt   => 'https://twitter.com/%s'
                      , regex => qr{(?:www\.)?twitter\.com/([^?\/ ]{1,16})(?:[?/].*)?} },
        l_anidb    => { label => 'AniDB'
                      , fmt   => 'https://anidb.net/cr%s'
                      , regex => qr{anidb\.net/(?:cr|creator/)([1-9][0-9]*)} },
        l_pixiv    => { label => 'Pixiv'
                      , fmt   => 'https://www.pixiv.net/member.php?id=%d'
                      , regex => qr{www\.pixiv\.net/member\.php\?id=([0-9]+)} },
        l_vgmdb    => { label => 'VGMdb'
                      , fmt   => 'https://vgmdb.net/artist/%d'
                      , regex => qr{vgmdb\.net/artist/([0-9]+)} },
        l_discogs  => { label => 'Discogs'
                      , fmt   => 'https://www.discogs.com/artist/%d'
                      , regex => qr{(?:www\.)?discogs\.com/artist/([0-9]+)(?:[?/-].*)?} },
        l_mobygames=> { label => 'MobyGames'
                      , fmt   => 'https://www.mobygames.com/person/%d'
                      , regex => qr{(?:www\.)?mobygames\.com/person/([0-9]+)(?:[?/].*)?} },
        l_bgmtv    => { label => 'Bangumi'
                      , fmt   => 'https://bgm.tv/person/%d'
                      , regex => qr{(?:www\.)?(?:bgm|bangumi)\.tv/person/([0-9]+)(?:[?/].*)?} },
        l_imdb     => { label => 'IMDb'
                      , fmt   => 'https://www.imdb.com/name/nm%07d'
                      , regex => qr{(?:www\.)?imdb\.com/name/nm([0-9]{7})(?:[?/].*)?} },
        l_mbrainz  => { label => 'MusicBrainz'
                      , fmt   => 'https://musicbrainz.org/artist/%s'
                      , regex => qr{musicbrainz\.org/artist/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})} },
        l_scloud   => { label => 'SoundCloud'
                      , fmt   => 'https://soundcloud.com/%s'
                      , regex => qr{soundcloud\.com/([a-z0-9-]+)} },
        l_vndb     => { label => 'VNDB user'
                      , fmt   => 'https://vndb.org/%s'
                      , regex => qr{vndb\.org/(u[1-9][0-9]*)} },
        # deprecated
        l_wp       => { label => 'Wikipedia',        fmt => 'https://en.wikipedia.org/wiki/%s' },
    },
    p => {
        website    => { label => 'Official website', fmt => '%s' },
        l_wikidata => { label => 'Wikidata',         fmt => 'https://www.wikidata.org/wiki/Q%d' },
        # deprecated
        l_wp       => { label => 'Wikipedia',        fmt => 'https://en.wikipedia.org/wiki/%s' },
    },
);


# Return a list of columns to fetch all external links for a database entry.
sub sql_extlinks {
    my($type, $prefix) = @_;
    $prefix ||= '';
    my $l = $LINKS{$type} || die "DB entry type $type has no links";
    join ',', map $prefix.$_, sort keys %$l
}


# Fetch a list of links to display at the given database entries, adds the
# following field to each object:
#
#   extlinks => [
#     { name, label, id, url, url2, price },  # depending on which fields are $enabled
#     ..
#   ]
#
# Assumes the columns returned by sql_extlinks() are already available.
sub enrich_extlinks {
    my($type, $enabled, @obj) = @_;
    $enabled ||= { label => 1, url2 => 1, price => 1 };
    @obj = map ref $_ eq 'ARRAY' ? @$_ : ($_), @obj;

    my $l = $LINKS{$type} || die "DB entry type $type has no links";

    my @w_ids = grep $_, map $_->{l_wikidata}, @obj;
    my $w = @w_ids ? { map +($_->{id}, $_), $TUWF::OBJ->dbAlli('SELECT * FROM wikidata WHERE id IN', \@w_ids)->@* } : {};

    # Fetch shop info for releases
    my @cleanup;
    if($type eq 'r') {
        VNWeb::DB::enrich_merge(id => q{
            SELECT r.id
                 ,       smg.price AS l_mg_price,       smg.r18 AS l_mg_r18
                 ,    sdenpa.price AS l_denpa_price
                 ,     sjast.price AS l_jast_price,     sjast.slug AS l_jast_slug
                 ,    sjlist.price AS l_jlist_price
                 ,   sdlsite.price AS l_dlsite_price,   sdlsite.shop AS l_dlsite_shop
              FROM releases r
              LEFT JOIN shop_denpa  sdenpa    ON    sdenpa.id = r.l_denpa    AND    sdenpa.lastfetch IS NOT NULL AND    sdenpa.deadsince IS NULL
              LEFT JOIN shop_dlsite sdlsite   ON   sdlsite.id = r.l_dlsite   AND   sdlsite.lastfetch IS NOT NULL AND   sdlsite.deadsince IS NULL
              LEFT JOIN shop_jastusa sjast    ON     sjast.id = r.l_jastusa  AND     sjast.lastfetch IS NOT NULL AND     sjast.deadsince IS NULL
              LEFT JOIN shop_jlist  sjlist    ON    sjlist.id = r.l_jlist    AND    sjlist.lastfetch IS NOT NULL AND    sjlist.deadsince IS NULL
              LEFT JOIN shop_mg     smg       ON       smg.id = r.l_mg       AND       smg.lastfetch IS NOT NULL AND       smg.deadsince IS NULL
              WHERE r.id IN},
              grep $_->{l_mg}||$_->{l_denpa}||$_->{l_jastusa}||$_->{l_jlist}||$_->{l_dlsite}, @obj
        ) if $enabled->{price} || $enabled->{url2};

        if(grep exists $_->{gtin}, @obj) {
            VNWeb::DB::enrich(l_playasia => gtin => gtin =>
                "SELECT gtin, price, url FROM shop_playasia WHERE price <> '' AND gtin IN",
                grep $_->{gtin}, @obj
            );
        } else {
            VNWeb::DB::enrich(l_playasia => id => id =>
                "SELECT r.id, s.gtin, s.price, s.url FROM releases r JOIN shop_playasia s ON s.gtin = r.gtin WHERE s.price <> '' AND r.id IN",
                @obj
            );
        }

        @cleanup = qw{l_mg_price l_mg_r18 l_denpa_price l_jast_price l_jast_slug l_jlist_price l_dlsite_price l_dlsite_shop l_playasia};
    }

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
            my($v, $fmt, $fmt2, $label) = ($obj->{$f}, $l->{$f} ? @{$l->{$f}}{'fmt', 'fmt2', 'label'} : ());
            push @links, map +{
                $enabled->{name}  ? (name  => $_[0] =~ s/^l_//r) : (),
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

        l 'l_site';
        l 'website';
        w 'enwiki';
        w 'jawiki';
        l 'l_wikidata';

        # VN links
        if($type eq 'v') {
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
            c 'vnstat', 'VNStat', 'https://vnstat.net/novel/%d', $obj->{id} =~ s/^.//r if $obj->{c_votecount}>=20;
        }

        # Release links
        if($type eq 'r') {
            l 'l_egs';
            l 'l_steam';
            c 'steamdb', 'SteamDB', 'https://steamdb.info/app/%d/info', $obj->{l_steam} if $obj->{l_steam};
            l 'l_dlsite', $obj->{l_dlsite_price};
            l 'l_gog';
            l 'l_itch';
            l 'l_patreonp';
            l 'l_patreon';
            l 'l_substar';
            l 'l_gamejolt';
            l 'l_denpa', $obj->{l_denpa_price};
            l 'l_jlist', $obj->{l_jlist_price};
            l 'l_jastusa', $obj->{l_jast_price};
            l 'l_fakku';
            l 'l_appstore';
            l 'l_googplay';
            l 'l_animateg';
            l 'l_freem';
            l 'l_freegame';
            l 'l_novelgam';
            l 'l_gyutto';
            l 'l_digiket';
            l 'l_melon';
            l 'l_melonjp';
            l 'l_mg', $obj->{l_mg_price};
            l 'l_nutaku';
            l 'l_getchu';
            l 'l_getchudl';
            l 'l_dmm';
            l 'l_toranoana';
            l 'l_booth';
            l 'l_playstation_jp';
            l 'l_playstation_na';
            l 'l_playstation_eu';
            l 'l_playstation_hk';
            l 'l_nintendo';
            l 'l_nintendo_jp';
            l 'l_nintendo_hk';
            c 'playasia', 'PlayAsia', '%s', $_->{url}, $_->{price} for $obj->{l_playasia}->@*;
        }

        # Staff links
        if($type eq 's') {
            l 'l_twitter'; w 'twitter'      if !$obj->{l_twitter};
            l 'l_anidb';   w 'anidb_person' if !$obj->{l_anidb};
            l 'l_pixiv';   w 'pixiv_user'   if !$obj->{l_pixiv};
            l 'l_mbrainz'; w 'musicbrainz_artist' if !$obj->{l_mbrainz};
            l 'l_vgmdb';   w 'vgmdb_artist' if !$obj->{l_vgmdb};
            l 'l_discogs'; w 'discogs_artist' if !$obj->{l_discogs};
            l 'l_scloud';  w 'soundcloud'   if !$obj->{l_scloud};
            l 'l_mobygames';
            l 'l_bgmtv';
            l 'l_imdb';
            l 'l_vndb';
            #w 'doujinshi_author';
        }

        # Producer links
        if($type eq 'p') {
            w 'twitter';
            w 'mobygames_company';
            w 'gamefaqs_company';
            #w 'doujinshi_author';
            w 'soundcloud';
            c 'vnstat', 'VNStat', 'https://vnstat.net/developer/%d', $obj->{id} =~ s/^.//r;
        }

        $obj->{extlinks} = \@links;
        delete @{$obj}{ @cleanup };
    }
}


# Returns a list of @fields for use in VNWeb::HTML::revision_()
sub revision_extlinks {
    my($type) = @_;
    map {
        my($f, $p) = ($_, $LINKS{$type}{$_});
        [ $f, $p->{label}, fmt => sub { TUWF::XML::a_(href => sprintf($p->{fmt}, $_), $_); }, empty => 0 ]
    } sort keys $LINKS{$type}->%*
}


# Turn a 'regex' value in %LINKS into a full proper regex.
sub full_regex { qr{^(?:https?://)?$_[0](?:\#.*)?$} }


# Returns a list of keys for inclusion into a TUWF::Validate schema.
# Only includes links for which a 'regex' has been set.
sub validate_extlinks {
    my($type) = @_;
    my($schema) = grep +($_->{dbentry_type}||'') eq $type, values VNDB::Schema::schema->%*;

    map {
        my($f, $p) = ($_, $LINKS{$type}{$_});
        my($s) = grep $_->{name} eq $f, $schema->{cols}->@*;

        my %val;
        $val{int} = 1 if $s->{type} =~ /^(big)?int/;
        $val{maxlength} = 512 if !$val{int};
        $val{func} = sub { $val{int} && !$_[0] ? 1 : sprintf($p->{fmt}, $_[0]) =~ full_regex $p->{regex} };
        ($f, $s->{type} =~ /\[\]/
            ? { type => 'array', values => \%val }
            : { default => $s->{decl} !~ /not\s+null/i ? undef : $val{int} ? 0 : '', %val }
        )
    } sort grep $LINKS{$type}{$_}{regex}, keys $LINKS{$type}->%*
}


# Returns a list of sites for use in VNWeb::Elm and util/jsgen.pl:
# { id => $id, name => $label, fmt => $label, regex => $regex, int => $bool, default => undef||0||''||[], pattern => [..] }
sub extlinks_sites {
    my($type) = @_;
    my($schema) = grep +($_->{dbentry_type}||'') eq $type, values VNDB::Schema::schema->%*;
    map {
        my($f, $p) = ($_, $LINKS{$type}{$_});
        my($s) = grep $_->{name} eq $f, $schema->{cols}->@*;
        my $patt = $p->{patt} || ($p->{fmt} =~ s/%s/<code>/rg =~ s/%[0-9]*d/<number>/rg);
        +{ id => $f, name => $p->{label}, fmt => $p->{fmt}, regex => full_regex($p->{regex})
         , int => $s->{type} =~ /^(big)?int/ ? 1 : 0,
         , default => $s->{type} =~ /\[\]/ ? [] : $s->{decl} !~ /not\s+null/i ? undef : $s->{type} =~ /^(big)?int/ ? 0 : ''
         , pattern => [ split /(<[^>]+>)/, $patt ] }
    } sort grep $LINKS{$type}{$_}{regex}, keys $LINKS{$type}->%*
}

1;
