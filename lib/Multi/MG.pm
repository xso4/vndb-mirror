package Multi::MG;

use v5.36;
use Multi::Core;
use AnyEvent::HTTP;
use VNDB::Config;


my %C = (
  r18  => 'https://www.mangagamer.com/r18/detail.php?product_code=',
  main => 'https://www.mangagamer.com/detail.php?product_code=',
  check_timeout => 10*60, # Minimum time between fetches.
);


sub run {
  shift;
  $C{ua} = sprintf 'VNDB.org Affiliate Crawler (Multi v%s; contact@vndb.org)', config->{version};
  %C = (%C, @_);
  push_watcher schedule 0, $C{check_timeout}, \&sync;
}


sub trysite {
  my($main, $id) = @_;
  my $ts = AE::now;
  my $url = ($main ? $C{main} : $C{r18}).$id;
  http_get $url, headers => {'User-Agent' => $C{ua} }, timeout => 60,
    sub { data($main, AE::now-$ts, $id, @_) };
}


sub data {
  my($main, $time, $id, $body, $hdr) = @_;
  my $prefix = sprintf '[%.1fs] %s', $time, $id;
  return AE::log warn => "$prefix ERROR: $hdr->{Status} $hdr->{Reason}" if $hdr->{Status} !~ /^2/ && $hdr->{Status} ne '404';

  my $found = $hdr->{Status} ne '404' && $body =~ /title_information\.png/;
  my $price = $body =~ /<b>\$(\d+\.\d+)<\/b>.+<b>MG point:/ ? sprintf('US$ %.2f', $1) : '';

  return AE::log warn => "$prefix Product found, but no price" if !$price && $found;

  # We have a price? Update database.
  if($price) {
    pg_cmd q{UPDATE extlinks SET deadsince = NULL, data = $2, price = $3, lastfetch = NOW() WHERE site = 'mg' AND value = $1}, [ $id, $main, $price ];
    AE::log debug => "$prefix for $price on r18=".($main?'f':'t');

  # Try /r18/
  } elsif($main) {
    trysite undef, $id;

  # Nothing? Update DB
  } else {
    pg_cmd q{UPDATE extlinks SET deadsince = COALESCE(deadsince, NOW()), lastfetch = NOW() WHERE site = 'mg' AND value = $1}, [ $id ];
    AE::log info => "$prefix not found.";
  }
}


sub sync {
  pg_cmd "SELECT value FROM extlinks WHERE site = 'mg' AND c_ref ORDER BY lastfetch ASC NULLS FIRST LIMIT 1", [], sub {
    my($res, $time) = @_;
    return if pg_expect $res, 1 or !$res->nRows;
    trysite 1, $res->value(0,0);
  };
}
