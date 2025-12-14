package VNTask::EL::GooglePlay;

use v5.36;
use VNTask::ExtLinks;
use FU::Util 'json_parse';
use VNDB::Func 'fmtdate';

sub fetch($task, $lnk) {
    my $res = http_get $lnk->url.'&hl=en&gl=us';
    $res->dead('Not found') if $res->code eq 404;
    $res->expect(200);

    # Google Play "HTML" is absolute garbage. A bunch of JS array dumps where
    # fields are found at fixed indices. The app info is in the array marked as
    # "ds:5". I hope these numbers are somewhat stable.
    my $ds5;
    my $body = $res->body;
    while ($body =~ m{<script[^>]+>AF_initDataCallback\s*\((.*?)\s*\)\s*;?\s*</script>}sg) {
        my $arg = $1;
        next if $arg !~ /key\s*:\s*['"]ds:5['"]/;
        $arg =~ s/^.*?data://;
        $arg =~ s/,\s*sideChannel\s*:.*$//;
        $ds5 = json_parse $arg, utf8 => 1;
        last;
    }
    die "No ds:5 data found\n" if !$ds5;

    # Indices from https://github.com/Mohammedcha/gplay-scraper/blob/main/gplay_scraper/models/element_specs.py#L287
    my $title = $ds5->[1][2][0][0];
    my $price = $ds5->[1][2][57][0][0][0][0][1][0][0];
    my $currency = $ds5->[1][2][57][0][0][0][0][1][0][1];
    my $originalPrice = $ds5->[1][2][57][0][0][0][0][1][1][0];
    my $offersIAP = !!$ds5->[1][2][19][0];
    my $developer = $ds5->[1][2][68][0];
    my $contentRating = $ds5->[1][2][9][0];
    my $containsAds = !!$ds5->[1][2][48];
    my $released = $ds5->[1][2][10][0];
    my $updated = $ds5->[1][2][145][0][1][0]; # // $ds5->[1][2][103]["146"][0][0] // $ds5->[1][2][145][0][0] // $ds5->[1][2][112]["146"][0][0] // $ds5->[1][2][103]["146"][0][1][0];
    my $version = $ds5->[1][2][140][0][0][0]; # // $ds5->[1][2][103]["141"][0][0][0];
    my $available = !!$ds5->[1][2][18][0];

    die "No title or developer\n" if !length $title || !length $developer;

    $price //= $originalPrice;
    $price = !defined $price ? undef : !$price ? 'free' : $currency ? sprintf '%.2f %s', $price/1000000, $currency : undef;

    $updated &&= fmtdate $updated;

    $lnk->save(price => $price, detail => {
        title => $title,
        developer => $developer,
        iap => $offersIAP,
        ads => $containsAds,
        $released ? (released => $released) : (),
        $updated ? (updated => $updated) : (),
        $version ? (version => $version) : (),
        $contentRating ? (rating => $contentRating) : (),
        available => $available,
    });
    $task->done;
}

el_queue 'el/googplay',
    freq   => '30d',
    triage => sub($lnk) { $lnk->site eq 'googplay' },
    \&fetch;

1;

