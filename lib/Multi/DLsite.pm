package Multi::DLsite;

use v5.36;
use utf8;
use Encode 'decode_utf8';
use Multi::Core;
use AnyEvent::HTTP;
use VNDB::Config;


my %C = (
  url => 'https://www.dlsite.com/%s/work/=/product_id/%s.html',
  clean_timeout => 48*3600,
  check_timeout => 1*60,
);


sub run {
  shift;
  $C{ua} = sprintf 'VNDB.org Affiliate Crawler (Multi v%s; contact@vndb.org)', config->{version};
  %C = (%C, @_);

  push_watcher schedule 0, $C{clean_timeout}, sub {
    pg_cmd q{DELETE FROM shop_dlsite WHERE id NOT IN(SELECT l_dlsite FROM releases WHERE NOT hidden)};
  };
  push_watcher schedule 0, $C{check_timeout}, sub {
    pg_cmd q{
      INSERT INTO shop_dlsite (id)
      SELECT DISTINCT l_dlsite
        FROM releases
       WHERE NOT hidden AND l_dlsite <> ''
         AND NOT EXISTS(SELECT 1 FROM shop_dlsite WHERE id = l_dlsite)
    }, [], \&sync
  }
}


sub data {
  my($shop, $time, $id, $body, $hdr) = @_;
  my $prefix = sprintf '[%.1fs] %s', $time, $id;
  #use Data::Dumper 'Dumper'; AE::log warn => Dumper $hdr, $body; exit;
  return AE::log warn => "$prefix ERROR: $hdr->{Status} $hdr->{Reason}" if $hdr->{Status} !~ /^2/ && $hdr->{Status} ne '404';

  $body = decode_utf8($body);
  my $found = $hdr->{Status} ne '404' && $body =~ /"id":"\Q$id\E",/;

  my $price =
    $body =~ m{<div class="work_buy_content"><span class="price">([0-9,]+)<i>円</i></span></div>} ? sprintf('JP¥ %d', $1 =~ s/,//gr) :
    $body =~ m{<i class="work_jpy">([0-9,]+) JPY</i></span>} ? sprintf('JP¥ %d', $1 =~ s/,//gr) : '';

  $shop = $body =~ /,"category":"([^"]+)"/ ? $1 : '';

  return AE::log warn => "$prefix Product found, but no price ($price) or shop ($shop)" if $found && (!$price || !$shop);

  # We have a price? Update database.
  if($price && $shop) {
    pg_cmd q{UPDATE shop_dlsite SET deadsince = NULL, shop = $2, price = $3, lastfetch = NOW() WHERE id = $1}, [ $id, $shop, $price ];
    AE::log debug => "$prefix for $price at /$shop/";

  # Nothing? Update DB
  } else {
    pg_cmd q{UPDATE shop_dlsite SET deadsince = COALESCE(deadsince, NOW()), lastfetch = NOW() WHERE id = $1}, [ $id ];
    AE::log info => "$prefix not found.";
  }
}


sub fetch {
  my($shop, $id) = @_;
  my $ts = AE::now;
  my $url = sprintf $C{url}, $shop, $id;
  http_get $url, headers => {'User-Agent' => $C{ua} }, timeout => 60,
    sub { data($shop, AE::now-$ts, $id, @_) };
}


sub sync {
  pg_cmd 'SELECT id, shop FROM shop_dlsite ORDER BY lastfetch ASC NULLS FIRST LIMIT 1', [], sub {
    my($res, $time) = @_;
    return if pg_expect $res, 1 or !$res->nRows;
    fetch 'home', $res->value(0,0);
  };
}
