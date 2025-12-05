package VNTask::EL::GOG;

use v5.36;
use VNTask::ExtLinks;
use FU::Util 'json_parse';

sub fetch($task, $lnk) {
    my $res = http_get $lnk->url;
    $res->dead('Not found') if $res->code eq 404 || $res->location =~ '/games$';
    $res->expect(200);

    my $ldjson = $res->body =~ m{<script type="application/ld\+json">(.*?)</script>}s ? $1 : $res->err('No embedded json metadata found');
    my $json = json_parse $ldjson;

    my $sku = ref $json eq 'HASH' && $json->{sku} && $json->{sku} =~ /^[0-9]+$/ ? $json->{sku} : $res->err('No SKU found');
    my($price) = grep $_->{availability} eq 'https://schema.org/InStock' && $_->{areaServed} =~ /^(US|REST)$/ && $_->{priceCurrency} eq 'USD', $json->{offers}->@*;
    $price = !$price ? undef : $price->{price} ? sprintf '%.02f USD', $price->{price} : 'free';

    $lnk->save(data => $sku, price => $price, detail => { name => $json->{name} });
    $task->done("%s at %d", $price || 'Unavailable', $sku);
}

el_queue 'el/gog',
    delay  => '30m',
    freq   => '30d',
    triage => sub($lnk) { $lnk->site eq 'gog' },
    \&fetch;

1;
