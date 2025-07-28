package VNTask::EL::WooCommerce;

# Fetcher for WooCommerce-based shops: Denpasoft & J-List.
# Assumes the store currency is USD.

use v5.36;
use VNTask::ExtLinks;

sub fetch($task, $lnk, $uri) {
    my $res = http_get $uri, task => 'Affiliate Crawler';
    warn "ERROR: Unexpected response: $res->{Status} $res->{Reason}\n" if $res->{Status} !~ /^(2|404)/;

    # JSON-LD
    my $found = $res->{Status} eq 200 && $res->{Body} =~ /"\@type":"Product"/;
    my $outofstock = $res->{Body} !~ m{"availability":"https?:\\?/\\?/schema\.org\\?/InStock"};
    my $price = $res->{Body} =~ /"price":"([0-9\.]+)"/ ? ($1 eq '0.00' ? 'free' : sprintf('US$ %.2f', $1)) : '';

    if ($outofstock) {
        $lnk->save(price => '');
        $task->done('Out of stock');
    } elsif ($price) {
        $lnk->save(price => $price);
        $task->done('Available for %s', $price);
    } else {
        warn "ERROR: Product found but no price\n" if $found;
        $lnk->save(dead => 1);
        $task->done('Not found');
    }
}

el_queue 'el/denpasoft',
    delay  => '5m',
    freq   => '3d',
    triage => sub($lnk) { $lnk->site eq 'denpa' },
    sub($task, $lnk) { fetch $task, $lnk, sprintf $LINKS{denpa}{fmt}, $lnk->value };

el_queue 'el/jlist',
    delay  => '10m',
    freq   => '3d',
    triage => sub($lnk) { $lnk->site eq 'jlist' },
    sub($task, $lnk) { fetch $task, $lnk, sprintf $LINKS{jlist}{fmt}, $lnk->value };

1;
