package VNTask::EL::AppStore;

use v5.36;
use VNTask::ExtLinks;


sub try($task, $lnk, $region=0) {
    my $res = http_get 'https://itunes.apple.com/lookup?id='.$lnk->value . ($region ? '&country='.$lnk->data : '');
    $res->expect(200);
    my $data = $res->json;

    if ($data->{resultCount} >= 1) {
        # API includes some pretty useful information, may be worth storing somewhere...
        $lnk->save($region ? () : (data => ''));
        $task->done('Found at %s', $region ? $lnk->data : 'regionless');
        return 1;
    } elsif ($region || !$lnk->data) {
        $lnk->save(dead => 1);
        $task->done('Not found');
        return 1;
    } else {
        return 0;
    }
}

el_queue 'el/appstore',
    delay  => '30m',
    freq   => '60d',
    triage => sub($lnk) { $lnk->site eq 'appstore' },
    # Try fetching without the region first, most products aren't region-locked.
    sub($task, $lnk) { try $task, $lnk or try $task, $lnk, 1 };

1;
