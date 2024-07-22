package Multi::Denpa;

use v5.36;
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
  };
}


sub data {
  my($time, $id, $body, $hdr) = @_;
  my $prefix = sprintf '[%.1fs] %s', $time, $id;
  return AE::log warn => "$prefix ERROR: $hdr->{Status} $hdr->{Reason}" if $hdr->{Status} !~ /^(2|404)/;

  # Same WooCommerce JSON-LD as J-List.
  my $found = $hdr->{Status} ne '404' && $body =~ /"\@type":"Product"/;
  my $outofstock = $body !~ m{"availability":"https?:\\?/\\?/schema\.org\\?/InStock"};
  my $price = $body =~ /"price":"([0-9\.]+)"/ ? ($1 eq '0.00' ? 'free' : sprintf('US$ %.2f', $1)) : '';

  # Out of stock? Update database.
  if($outofstock) {
    pg_cmd q{UPDATE shop_denpa SET deadsince = NULL, price = '', lastfetch = NOW() WHERE id = $1}, [ $id ];
    AE::log debug => "$prefix is out of stock";

  # We have a price? Update database.
  } elsif($price) {
    pg_cmd q{UPDATE shop_denpa SET deadsince = NULL, price = $2, lastfetch = NOW() WHERE id = $1}, [ $id, $price ];
    AE::log debug => "$prefix for $price";

  # Not found? Update database.
  } else {
    pg_cmd q{UPDATE shop_denpa SET deadsince = NOW() WHERE deadsince IS NULL AND id = $1}, [ $id ];
    AE::log info => "$prefix not found.";
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
