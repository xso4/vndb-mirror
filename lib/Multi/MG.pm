package Multi::MG;

use v5.36;
use Multi::Core;
use AnyEvent::HTTP;
use VNDB::Config;


my %C = (
  r18  => 'https://www.mangagamer.com/r18/detail.php?product_code=',
  main => 'https://www.mangagamer.com/detail.php?product_code=',
  clean_timeout => 48*3600,
  check_timeout => 10*60, # Minimum time between fetches.
);


sub run {
  shift;
  $C{ua} = sprintf 'VNDB.org Affiliate Crawler (Multi v%s; contact@vndb.org)', config->{version};
  %C = (%C, @_);

  push_watcher schedule 0, $C{clean_timeout}, sub {
    pg_cmd 'DELETE FROM shop_mg WHERE id NOT IN(SELECT l_mg FROM releases WHERE NOT hidden)';
  };
  push_watcher schedule 0, $C{check_timeout}, sub {
    pg_cmd q{
      INSERT INTO shop_mg (id)
      SELECT DISTINCT l_mg
        FROM releases
       WHERE NOT hidden AND l_mg <> 0
         AND NOT EXISTS(SELECT 1 FROM shop_mg WHERE id = l_mg)
    }, [], \&sync
  }
}


sub trysite {
  my($r18, $id) = @_;
  my $ts = AE::now;
  my $url = ($r18 eq 't' ? $C{r18} : $C{main}).$id;
  http_get $url, headers => {'User-Agent' => $C{ua} }, timeout => 60,
    sub { data($r18, AE::now-$ts, $id, @_) };
}


sub data {
  my($r18, $time, $id, $body, $hdr) = @_;
  my $prefix = sprintf '[%.1fs] %s', $time, $id;
  return AE::log warn => "$prefix ERROR: $hdr->{Status} $hdr->{Reason}" if $hdr->{Status} !~ /^2/ && $hdr->{Status} ne '404';

  my $found = $hdr->{Status} ne '404' && $body =~ /title_information\.png/;
  my $price = $body =~ /<b>\$(\d+\.\d+)<\/b>.+<b>MG point:/ ? sprintf('US$ %.2f', $1) : '';

  return AE::log warn => "$prefix Product found, but no price" if !$price && $found;

  # We have a price? Update database.
  if($price) {
    pg_cmd q{UPDATE shop_mg SET deadsince = NULL, r18 = $2, price = $3, lastfetch = NOW() WHERE id = $1}, [ $id, $r18, $price ];
    AE::log debug => "$prefix for $price on r18=$r18";

  # Try /r18/
  } elsif($r18 eq 'f') {
    trysite 't', $id;

  # Nothing? Update DB
  } else {
    pg_cmd q{UPDATE shop_mg SET deadsince = COALESCE(deadsince, NOW()), lastfetch = NOW() WHERE id = $1}, [ $id ];
    AE::log info => "$prefix not found.";
  }
}


sub sync {
  pg_cmd 'SELECT id FROM shop_mg ORDER BY lastfetch ASC NULLS FIRST LIMIT 1', [], sub {
    my($res, $time) = @_;
    return if pg_expect $res, 1 or !$res->nRows;
    trysite 'f', $res->value(0,0);
  };
}
