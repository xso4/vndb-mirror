package VNTask::EL::MangaGamer;

use v5.36;
use VNTask::ExtLinks;

my $r18url  = 'https://www.mangagamer.com/r18/detail.php?product_code=';
my $mainurl = 'https://www.mangagamer.com/detail.php?product_code=';

sub trysite($task, $lnk, $main) {
    my $uri = +($main ? $mainurl : $r18url).$lnk->value;
    my $res = http_get $uri, task => 'Affiliate Crawler';
    warn "ERROR: Unexpected response: $res->{Status} $res->{Reason}\n" if $res->{Status} !~ /^(2|3|404)/;

    my $found = $res->{Status} eq 200 && $res->{Body} =~ /title_information\.png/;
    my $price = $res->{Body} =~ /<b>\$(\d+\.\d+)<\/b>.+<b>MG point:/ ? sprintf('US$ %.2f', $1) : '';

    if ($found && $price) {
        $lnk->save(data => $main, price => $price);
        $task->done('Available at %s for %s', $main ? 'main' : 'r18', $price);
        return 1
    } else {
        warn "ERROR: Product found but no price\n" if $found;
        return 0
    }
}

el_queue 'el/mangagamer',
    delay  => '5m',
    freq   => '3d',
    triage => sub($lnk) { $lnk->site eq 'mg' },
    sub($task, $lnk) {
        return if trysite $task, $lnk, 1;
        sleep 5; # Let's be nice
        return if trysite $task, $lnk, '';
        $lnk->save(dead => 1);
        $task->done('Not found');
    };

1;
