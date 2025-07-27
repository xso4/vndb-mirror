package VNTask::EL::DLsite;

use v5.36;
use utf8;
use VNTask::Core;
use VNTask::ExtLinks;
use VNDB::ExtLinks;

sub fetch($task, $lnk) {
    my $id = $lnk->value;
    my $uri = sprintf $VNDB::ExtLinks::LINKS{dlsite}{fmt}, $id;

    my $res = http_get $uri, task => 'Affiliate Crawler';
    warn "ERROR: Unexpected response: $res->{Status} $res->{Reason}\n" if $res->{Status} !~ /^(2|3|404)/;

    my $shop = 'home';
    if ($res->{Status} =~ /^3/) {
        if ($res->{location} =~ m{^https://www\.dlsite\.com/([a-z]+)/work/=/product_id/\Q$id\E\.html$}) {
            $shop = $1;
            $res = http_get $res->{location}, task => 'Affiliate Crawler';
        } else {
            warn "ERROR: Redirect to unexpected location: $res->{location}\n";
        }
    }

    my $found = $res->{Status} ne 404 && $res->{Body} =~ /"id":"\Q$id\E",/;

    my $price =
        $res->{Body} =~ m{<div class="work_buy_content"><span class="price">([0-9,]+)<i>円</i></span></div>} ? sprintf('JP¥ %d', $1 =~ s/,//gr) :
        $res->{Body} =~ m{<i class="work_jpy">([0-9,]+) JPY</i></span>} ? sprintf('JP¥ %d', $1 =~ s/,//gr) :
        $res->{Body} =~ m{"price_with_tax":([0-9]+)} ? sprintf('JP¥ %d', $1) : ''; # <- still included on the page for geo-blocked products

    if ($found && $price) {
        $lnk->save(data => $shop, price => $price);
        $task->done("Available at /$shop/ for $price");
    } else {
        $lnk->save(dead => 1);
        $task->done($found ? "ERROR: Found but no price ($price)\n" : 'Not found');
    }
}

el_queue 'el/dlsite',
    delay  => '1m',
    freq   => '14d',
    triage => sub($lnk) { $lnk->site eq 'dlsite' },
    \&fetch;

1;
