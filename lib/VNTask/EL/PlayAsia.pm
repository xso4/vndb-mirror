package VNTask::EL::PlayAsia;

use v5.36;
use VNTask::ExtLinks;

return if !config->{playasia_api};

my @alpha = (0..9, 'a'..'z');
my %alpha = map +($alpha[$_], $_), 0..$#alpha;

# URL identifiers and PAX codes are just different representations of the same
# number, so we can convert between them.
sub value2pax($s) {
    my $v = 0;
    while ($s =~ s/^(.)//) { $v *= @alpha; $v += $alpha{$1} }
    sprintf 'PAX%010d', $v*17 + 17*17
}


sub fetch($task, $lnk) {
    my $uri = config->{playasia_api}.'&query=info&pax='.value2pax($lnk->value).'&mask=aps';
    my $res = http_get $uri, task => 'Affiliate Crawler';
    $res->expect(200);

    my $text = $res->text;
    $res->err($1) if $text =~ /<errorstring>\s*([^<]+)\s*<\/errorstring>/;
    $res->err('no URL found') if $text !~ /<affiliate_url>\s*([^<]+)\s*<\/affiliate_url>/;
    my $slug = $1 =~ m{^https://www\.play-asia\.com/([^/]+)/13/.*} ? $1 : '';
    my $onsale = $text =~ /<on_sale>\s*yes/ ? 1 : 0;
    my $price = $onsale && $text =~ /<price>\s*(\d+(?:\.\d+)?)\s*<\/price>/ && $1 ? sprintf('US$ %.2f', $1) : '';

    $lnk->save(price => $price, data => $slug);
    $task->done('%s at /%s/', $price ? "Available for $price" : 'Out of stock', $slug);
}

# PlayAsia API has pretty strict rate limits, we'll need a long update frequency.
el_queue 'el/playasia',
    delay  => '10m',
    freq   => '60d',
    triage => sub($lnk) { $lnk->site eq 'playasia' },
    \&fetch;

1;
