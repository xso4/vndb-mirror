package Multi::Denpa;

use strict;
use warnings;
use Multi::Core;
use AnyEvent::HTTP;
use VNDB::Config;
use VNDB::ExtLinks ();


my %C = (
  clean_timeout => 48*3600,
  check_timeout => 10*60,
);


sub run {
  shift;
  $C{ua} = sprintf 'VNDB.org Affiliate Crawler (Multi v%s; contact@vndb.org)', config->{version};
  %C = (%C, @_);

  push_watcher schedule 0, $C{clean_timeout}, sub {
    pg_cmd 'DELETE FROM shop_denpa WHERE id NOT IN(SELECT l_denpa FROM releases WHERE NOT hidden)';
  };
  push_watcher schedule 0, $C{check_timeout}, sub {
    pg_cmd q{
      INSERT INTO shop_denpa (id)
      SELECT DISTINCT l_denpa
        FROM releases
       WHERE NOT hidden AND l_denpa <> ''
         AND NOT EXISTS(SELECT 1 FROM shop_denpa WHERE id = l_denpa)
    }, [], \&sync
  }
}


sub data {
  my($time, $id, $body, $hdr) = @_;
  my $prefix = sprintf '[%.1fs] %s', $time, $id;
  return AE::log warn => "$prefix ERROR: $hdr->{Status} $hdr->{Reason}" if $hdr->{Status} !~ /^(2|404)/;

  my $listprice    = $body =~ m{<meta property="product:price:amount" content="([^"]+)"} && $1;
  my $currency     = $body =~ m{<meta property="product:price:currency" content="([^"]+)"} && $1;
  my $availability = $body =~ m{<meta property="product:availability" content="([^"]+)"} && $1;
  my $sku          = $body =~ m{<meta property="product:retailer_item_id" content="([^"]+)"} ? $1 : '';

  # Meta properties aren't set if the product has multiple SKU's (e.g. multi-platform), fall back to some json-ld string.
  ($listprice, $currency) = ($1,$2) if !$listprice && $body =~ /"priceSpecification":\{"price":"([^"]+)","priceCurrency":"([^"]+)"/;

  if($hdr->{Status} eq '404' || !$listprice || !$availability || $availability ne 'instock') {
    pg_cmd q{UPDATE shop_denpa SET deadsince = COALESCE(deadsince, NOW()), lastfetch = NOW() WHERE id = $1}, [ $id ];
    AE::log info => "$prefix not found or not in stock.";

  } else {
    my $price = $listprice eq '0.00' ? 'free' : ($currency eq 'USD' ? 'US$' : $currency).' '.$listprice;
    pg_cmd 'UPDATE shop_denpa SET deadsince = NULL, lastfetch = NOW(), sku = $2, price = $3 WHERE id = $1',
      [ $id, $sku, $price ];
    AE::log debug => "$prefix for $price at $sku";
  }
}


sub sync {
  pg_cmd 'SELECT id FROM shop_denpa ORDER BY lastfetch ASC NULLS FIRST LIMIT 1', [], sub {
    my($res, $time) = @_;
    return if pg_expect $res, 1 or !$res->nRows;

    my $id = $res->value(0,0);
    my $ts = AE::now;
    http_get sprintf($VNDB::ExtLinks::LINKS{r}{l_denpa}{fmt}, $id),
      headers => {'User-Agent' => $C{ua}},
      timeout => 60,
      sub { data(AE::now-$ts, $id, @_) };
  };
}

1;
