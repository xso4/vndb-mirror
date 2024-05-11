package Multi::JList;

use v5.36;
use Multi::Core;
use AnyEvent::HTTP;
use VNDB::Config;
use VNDB::ExtLinks;


my %C = (
  url => 'https://jlist.com/shop/product/%s',
  clean_timeout => 48*3600,
  check_timeout => 10*60, # Minimum time between fetches.
);


sub run {
  shift;
  $C{ua} = sprintf 'VNDB.org Affiliate Crawler (Multi v%s; contact@vndb.org)', config->{version};
  %C = (%C, @_);

  push_watcher schedule 0, $C{clean_timeout}, sub {
    pg_cmd 'DELETE FROM shop_jlist WHERE id NOT IN(SELECT l_jlist FROM releases WHERE NOT hidden)';
  };
  push_watcher schedule 0, $C{check_timeout}, sub {
    pg_cmd q{
      INSERT INTO shop_jlist (id)
      SELECT DISTINCT l_jlist
        FROM releases
       WHERE NOT hidden AND l_jlist <> ''
         AND NOT EXISTS(SELECT 1 FROM shop_jlist WHERE id = l_jlist)
    }, [], \&sync
  }
}


sub data {
  my($time, $id, $body, $hdr) = @_;
  my $prefix = sprintf '[%.1fs] %s', $time, $id;
  return AE::log warn => "$prefix ERROR: $hdr->{Status} $hdr->{Reason}" if $hdr->{Status} !~ /^2/ && $hdr->{Status} ne '404';

  # Extract info from the JSON-LD embedded on the page. Assumes there's either
  # a single "Product" or none. Also assumes specific JSON formatting, because
  # I'm too lazy to properly extract out and parse the JSON.
  my $found = $hdr->{Status} ne '404' && $body =~ /"\@type":"Product"/;
  my $outofstock = $body !~ m{"availability":"https://schema.org/InStock"};
  my $price = $body =~ /"price":"([0-9\.]+)"/ ? sprintf('US$ %.2f', $1) : '';

  return AE::log warn => "$prefix Product found, but no price" if !$price && $found && !$outofstock;

  # Out of stock? Update database.
  if($outofstock) {
    pg_cmd q{UPDATE shop_jlist SET deadsince = NULL, price = '', lastfetch = NOW() WHERE id = $1}, [ $id ];
    AE::log debug => "$prefix is out of stock";

  # We have a price? Update database.
  } elsif($price) {
    pg_cmd q{UPDATE shop_jlist SET deadsince = NULL, price = $2, lastfetch = NOW() WHERE id = $1}, [ $id, $price ];
    AE::log debug => "$prefix for $price";

  # Not found? Update database.
  } else {
    pg_cmd q{UPDATE shop_jlist SET deadsince = NOW() WHERE deadsince IS NULL AND id = $1}, [ $id ];
    AE::log info => "$prefix not found.";
  }
}


sub sync {
  pg_cmd 'SELECT id FROM shop_jlist ORDER BY lastfetch ASC NULLS FIRST LIMIT 1', [], sub {
    my($res, $time) = @_;
    return if pg_expect $res, 1 or !$res->nRows;
    my $id = $res->value(0,0);
    my $ts = AE::now;
    http_get sprintf($C{url}, $id), headers => {'User-Agent' => $C{ua} }, timeout => 60,
      sub { data(AE::now-$ts, $id, @_) };
  };
}
