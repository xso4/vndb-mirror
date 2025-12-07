package VNTask::EL::JASTUSA;

use v5.36;
use VNTask::ExtLinks;

sub fetch($task, $lnk) {
    # Requesting /games/$id without slug redirects to the page with the slug
    my $res = http_get 'https://jastusa.com/games/'.$lnk->value, task => 'Affiliate Crawler';
    $res->dead('Not found') if $res->code eq 404;

    $res->expect(3);
    my $loc = $res->location;
    $res->dead('Redirect to /') if $loc eq 'https://jastusa.com/';
    $res->err("Unexpected redirect to $loc") if $loc !~ m{/games/\Q$lnk->{value}\E/(.+)$};
    my $slug = $1;

    $res = http_get $loc, task => 'Affiliate Crawler';
    $res->expect(200);

    my $price =
        $res->{Body} =~ m{<div class="price-box__hld">.*<span class="price-box__value">\s*([0-9.]+)\s*</span>}s ? "US\$ $1" :
        $res->{Body} =~ m{<span class="sidebar-main__info">\s*Free item} ? 'free' :
        $res->err('No price information found');

    $lnk->save(price => $price, data => $slug);
    $task->done('Available at /%s for %s', $slug, $price);
}

el_queue 'el/jastusa',
    freq   => '4d',
    triage => sub($lnk) { $lnk->site eq 'jastusa' },
    \&fetch;

1;
