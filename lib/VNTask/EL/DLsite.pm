package VNTask::EL::DLsite;

use v5.36;
use utf8;
use VNTask::ExtLinks;

sub fetch($task, $lnk) {
    my $id = $lnk->value;
    my $res = http_get $lnk->url;
    $res->expect('2|3|404');

    my $shop = $lnk->data;
    if ($res->location) {
        # Some products just trigger a redirect to /home/ instead of a 404. Odd.
        $res->dead('Redirect to /home/') if $res->location =~ qr{/home/$};

        my ($site, $value, $data) = VNDB::ExtLinks::extlink_parse($res->location);
        if (!$site || $site ne 'dlsite' || $value ne $id) {
            $res->err('Redirect to unexpected location: '.$res->location);
        } else {
            $shop = $data;
            $res = http_get $res->location;
            $res->expect(200);
        }
    }

    my $body = $res->text;
    $res->dead('Not found') if $res->code eq 404 or $body !~ /"id":"\Q$id\E",/;

    my $price =
        $body =~ m{<div class="work_buy_content"><span class="price">([0-9,]+)<i>円</i></span></div>} ? sprintf('JP¥ %d', $1 =~ s/,//gr) :
        $body =~ m{<i class="work_jpy">([0-9,]+) JPY</i></span>} ? sprintf('JP¥ %d', $1 =~ s/,//gr) :
        $body =~ m{"price_with_tax":([0-9]+)} ? sprintf('JP¥ %d', $1) : # <- still included on the page for geo-blocked products
        $res->err('Unable to extract price information');

    $lnk->save(data => $shop, price => $price);
    $task->done("Available at /$shop/ for $price");
}

el_queue 'el/dlsite',
    delay  => '1m',
    freq   => '14d',
    triage => sub($lnk) { $lnk->site eq 'dlsite' },
    \&fetch;

1;
