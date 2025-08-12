package VNTask::EL::WooCommerce;

# Fetcher for WooCommerce-based shops: Denpasoft & J-List.
# Assumes the store currency is USD.

use v5.36;
use VNTask::ExtLinks;

sub fetch($task, $lnk) {
    my $res = http_get $lnk->url, task => 'Affiliate Crawler';
    $res->dead('Not found') if $res->code eq 404;
    $res->expect(200);

    # JSON-LD
    $res->dead('Not found') if $res->body !~ /"\@type":"Product"/;
    my $price =
        $res->body !~ m{"availability":"https?:\\?/\\?/schema\.org\\?/InStock"} ? '' :
        $res->body =~ /"price":"([0-9\.]+)"/ ? ($1 eq '0.00' ? 'free' : sprintf('US$ %.2f', $1)) :
        $res->err('No price information found');

    $lnk->save(price => $price);
    $task->done($price ? "Available for $price" : 'Out of stock');
}

el_queue 'el/denpasoft',
    delay  => '5m',
    freq   => '3d',
    triage => sub($lnk) { $lnk->site eq 'denpa' },
    \&fetch;

el_queue 'el/jlist',
    delay  => '10m',
    freq   => '3d',
    triage => sub($lnk) { $lnk->site eq 'jlist' },
    \&fetch;

1;
