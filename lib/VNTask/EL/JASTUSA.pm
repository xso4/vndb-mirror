package VNTask::EL::JASTUSA;

use v5.36;
use VNTask::ExtLinks;

sub fetch($task, $lnk) {
    # Requesting /games/$id without slug redirects to the page with the slug
    my $res = http_get 'https://jastusa.com/games/'.$lnk->value, task => 'Affiliate Crawler';
    warn "ERROR: Unexpected response: $res->{Status} $res->{Reason}\n" if $res->{Status} !~ /^(3|404)/;

    if ($res->{Status} !~ /^3/) {
        $lnk->save(dead => 1);
        return $task->done('Not found');
    }

    my $slug = ($res->{location}||'') =~ m{/games/\Q$lnk->{value}\E/(.+)$} && $1;
    if (!$slug) {
        $lnk->save(dead => 1);
        return $task->done("ERROR: Unexpected redirect to $res->{location}");
    }

    $res = http_get 'https://jastusa.com/games/'.$lnk->value.'/'.$slug, task => 'Affiliate Crawler';
    warn "ERROR: Unexpected response: $res->{Status} $res->{Reason}\n" if $res->{Status} ne 200;

    my $price =
        $res->{Body} =~ m{<div class="price-box__hld">.*<span class="price-box__value">\s*([0-9.]+)\s*</span>}s ? "US\$ $1" :
        $res->{Body} =~ m{<span class="sidebar-main__info">\s*Free item} ? 'free' : '';

    if ($price) {
        $lnk->save(price => $price, data => $slug);
        $task->done('Available at /%s for %s', $slug, $price);
    } else {
        $lnk->save(dead => 1);
        $task->done('ERROR: No price information found');
    }
}

el_queue 'el/jastusa',
    delay  => '10m',
    freq   => '3d',
    triage => sub($lnk) { $lnk->site eq 'jastusa' },
    \&fetch;

1;
