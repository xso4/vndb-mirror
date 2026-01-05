package VNTask::EL::AppStore;

use v5.36;
use VNTask::ExtLinks;


# Bad country code fallback for region-locked apps.
# Only includes country codes I've actually seen games being region-locked in.
my %lang2country = (
    ja         => [ 'jp' ],
    th         => [ 'th' ],
    zh         => [ 'ch', 'tw', 'hk' ],
    'zh-Hans'  => [ 'ch', 'tw', 'hk' ],
    'zh-Hant'  => [ 'ch', 'tw', 'hk' ],
    ko         => [ 'kr' ],
    ru         => [ 'ru' ],
    es         => [ 'es', 'pe' ],
);


sub try($task, $lnk, $region='') {
    my $res = http_get 'https://itunes.apple.com/lookup?id='.$lnk->value . ($region ? '&country='.$region : '');
    $res->expect(200);
    my $data = $res->json;
    $res->dead('Not found') if !$data->{resultCount};

    $data = $data->{results}[0];
    $lnk->save(
        data   => $region,
        price  => $data->{formattedPrice},
        detail => {
            developer => $data->{artistName},
            version   => $data->{version},
            bundleid  => $data->{bundleId},
            agerating => $data->{trackContentRating},
            released  => $data->{releaseDate},
        },
    );
    $task->done('Found at %s', $region || 'regionless');
}

el_queue 'el/appstore',
    freq   => '60d',
    triage => sub($lnk) { $lnk->site eq 'appstore' },
    sub($task, $lnk) {
        # Try fetching without the region first (implies country=US), most products aren't region-locked.
        return if eval { try $task, $lnk; 1 };

        # Try fetching with 'data' if we have that.
        return if $lnk->data && eval { try $task, $lnk, $lnk->data; 1 };

        # If that doesn't work, query the database for possible regions
        my %regions = map +($_,1), map @$_, grep $_, map $lang2country{$_}, $task->sql('
            SELECT DISTINCT rt.lang
              FROM releases_extlinks re
              JOIN releases r ON r.id = re.id
              JOIN releases_titles rt ON rt.id = r.id
             WHERE NOT r.hidden AND re.link = $1', $lnk->id
        )->flat->@*;
        delete $regions{ $lnk->data } if $lnk->data;
        eval { try $task, $lnk, $_; 1 } && return for sort keys %regions;
        die $@;
    };

1;
