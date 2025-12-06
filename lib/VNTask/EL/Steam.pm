package VNTask::EL::Steam;

use v5.36;
use VNTask::ExtLinks;

sub fetch($task, $lnk) {
    my $res = http_get 'https://store.steampowered.com/api/appdetails?cc=us&l=en&appids='.$lnk->value;
    $res->expect(200);
    my $json = $res->json->{$lnk->value};
    $res->dead('Not found') if !$json->{success};
    $json = $json->{data};

    my $price = $json->{is_free} ? 'free' : $json->{price_overview} ? sprintf 'US$ %.2f', $json->{price_overview}{final}/100 : undef;

    $lnk->save(price => $price, detail => {
        name => $json->{name},
        developers => $json->{developers},
        publishers => $json->{publishers},
        release_date => $json->{release_date}{date},
        (grep $_->{rating} && $_->{rating} eq '18', $json->{ratings} ? values $json->{ratings}->%* : ()) ? (r18 => !0) : (),
    });
    $task->done;
}

el_queue 'el/steam',
    delay  => '3m',
    freq   => '30d',
    triage => sub($lnk) { $lnk->site eq 'steam' },
    \&fetch;

1;

