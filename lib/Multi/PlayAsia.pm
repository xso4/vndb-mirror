package Multi::PlayAsia;

use v5.36;
use Multi::Core;
use AnyEvent::HTTP;
use VNDB::Config;

my %C = (
  api               => '',
  gtin_timeout      =>  1*60,
  info_timeout      =>  3*60,
  sync_gtin_timeout => 24*3600,
);


sub run {
  shift;
  $C{ua} = sprintf 'VNDB.org Affiliate Crawler (Multi v%s; contact@vndb.org)', config->{version};
  %C = (%C, @_);

  push_watcher schedule 0, $C{sync_gtin_timeout}, \&sync_gtin;
  push_watcher schedule 0, $C{gtin_timeout},      \&syncpax;
  push_watcher schedule 0, $C{info_timeout},      \&syncinfo;
}


sub sync_gtin {
  pg_cmd q{
      INSERT INTO shop_playasia_gtin (gtin)
      SELECT DISTINCT r.gtin
        FROM releases r
       WHERE r.gtin <> 0
         AND NOT r.hidden
         AND NOT EXISTS(SELECT 1 FROM shop_playasia_gtin spg WHERE spg.gtin = r.gtin)};
  pg_cmd q{
    DELETE FROM shop_playasia_gtin spg WHERE NOT EXISTS(
      SELECT 1 FROM releases r WHERE r.gtin = spg.gtin AND NOT r.hidden)};
}


sub pa_expect {
  my($body, $hdr, $prefix) = @_;

  if($hdr->{Status} !~ /^2/) {
    AE::log warn => "$prefix ERROR: $hdr->{Status} $hdr->{Reason}";
    return 1;
  }

  my $errorstr = $body =~ s/<errorstring>\s*([^<]+)\s*<\/errorstring>// ? $1 : undef;
  if($errorstr && !($body =~ /paxfrombarcode/ && $errorstr =~ /Unknown error/)) {
    AE::log warn => "$prefix ERROR: $errorstr";
    return 1;
  }

  return 0;
}


sub getpax {
  my $bc = shift;
  my $ts = AE::now;
  http_get "$C{api}&query=paxfrombarcode&bc=$bc", headers => {'User-Agent' => $C{ua} }, timeout => 60,
  sub {
    my($body, $hdr) = @_;
    my $time = AE::now-$ts;
    my $prefix = sprintf '[%.1fs] paxfrombarcode[%s]', $time, $bc;
    return if pa_expect $body, $hdr, $prefix;

    my @pax;
    push @pax, $1 while ($body =~ s/<pax>\s*([^<]+)\s*<\/pax>//);
    AE::log debug => "$prefix Got new paxes: @pax";

    pg_cmd 'UPDATE shop_playasia_gtin SET lastfetch = NOW() WHERE gtin = $1', [ $bc ];
    pg_cmd 'INSERT INTO shop_playasia (pax, gtin) VALUES ($1, $2) ON CONFLICT DO NOTHING', [ $_, $bc ] for (@pax);
    pg_cmd 'DELETE FROM shop_playasia WHERE gtin = $1', [ $bc ] if !@pax;
    my $lst = join ',', map "\$$_", 2..(@pax+1);
    pg_cmd "DELETE FROM shop_playasia WHERE gtin = \$1 AND pax NOT IN($lst)", [ $bc, @pax ] if @pax;
  };
}


sub syncpax {
  pg_cmd 'SELECT gtin FROM shop_playasia_gtin ORDER BY lastfetch ASC NULLS FIRST LIMIT 1', [],
  sub {
    my($res) = @_;
    return if pg_expect $res, 1 or !$res->nRows;
    getpax $res->value(0,0);
  }
}



sub getinfo {
  my $pax = shift;
  my $ts = AE::now;
  http_get "$C{api}&query=info&pax=$pax&mask=aps", headers => {'User-Agent' => $C{ua} }, timeout => 60,
  sub {
    my($body, $hdr) = @_;
    my $time = AE::now-$ts;
    my $prefix = sprintf '[%.1fs] info[%s]', $time, $pax;
    return if pa_expect $body, $hdr, $prefix;

    my $url = $body =~ /<affiliate_url>\s*([^<]+)\s*<\/affiliate_url>/ ? $1 : '';
    my $onsale = $body =~ /<on_sale>\s*yes/ ? 't' : 'f';
    my $price = $url && $onsale eq 't'
      && $body =~ /<price>\s*(\d+(?:\.\d+)?)\s*<\/price>/ && $1 ? sprintf('US$ %.2f', $1) : '';

    AE::log debug => "$prefix got price='$price' onsale=$onsale url=$url";
    pg_cmd
      q{UPDATE shop_playasia SET url = $2, price = $3, lastfetch = NOW() WHERE pax = $1},
      [ $pax, $url, $price ];
  };
}


sub syncinfo {
  pg_cmd 'SELECT pax FROM shop_playasia ORDER BY lastfetch ASC NULLS FIRST LIMIT 1', [],
  sub {
    my $res = shift;
    return if pg_expect $res, 1 or !$res->nRows;
    getinfo $res->value(0,0);
  };
}


1;
