package VNTask::EL::MangaGamer;

use v5.36;
use VNTask::ExtLinks;

sub trysite($task, $lnk, $main) {
    my $res = http_get $lnk->url($main), task => 'Affiliate Crawler';

    $res->dead('Not found') if $res->code eq 404 || $res->location =~ qr{/r18/index\.php$};
    $res->expect(200);
    $res->err('Not found') if $res->body !~ /title_information\.png/;

    my $price =
        $res->body =~ /<b>\$(\d+\.\d+)<\/b>.+<b>MG point:/ ? sprintf('US$ %.2f', $1) :
        $res->err('No price found');

    $lnk->save(data => $main, price => $price);
    $task->done('Available at %s for %s', $main ? 'main' : 'r18', $price);
}

el_queue 'el/mangagamer',
    freq   => '3d',
    triage => sub($lnk) { $lnk->site eq 'mg' },
    sub($task, $lnk) {
        return if eval { trysite $task, $lnk, 1; 1; };
        sleep 5; # Let's be nice
        trysite $task, $lnk, '';
    };

1;
