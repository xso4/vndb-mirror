package VNTask::EL::AppStore;

use v5.36;
use VNTask::ExtLinks;


sub try($task, $lnk, $region=0) {
    my $res = http_get 'https://itunes.apple.com/lookup?id='.$lnk->value . ($region ? '&country='.$lnk->data : '');
    $res->expect(200);
    my $data = $res->json;
    $res->dead('Not found') if !$data->{resultCount};

    $data = $data->{results}[0];
    $lnk->save(
        data   => $region ? $lnk->data : '',
        price  => $data->{formattedPrice},
        detail => {
            developer => $data->{artistName},
            version   => $data->{version},
            bundleid  => $data->{bundleId},
            agerating => $data->{trackContentRating},
            released  => $data->{releaseDate},
        },
    );
    $task->done('Found at %s', $region ? $lnk->data : 'regionless');
}

el_queue 'el/appstore',
    delay  => '30m',
    freq   => '60d',
    triage => sub($lnk) { $lnk->site eq 'appstore' },
    sub($task, $lnk) {
        # Try fetching without the region first, most products aren't region-locked.
        return if eval { try $task, $lnk, 0; 1 };
        try $task, $lnk, 1;
    };

1;
