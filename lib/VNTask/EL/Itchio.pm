package VNTask::EL::Itchio;

use v5.36;
use VNTask::ExtLinks;

# Uses the Itch.getGameData() API backend of https://itch.io/docs/api/javascript
sub fetch($task, $lnk) {
    my $res = http_get $lnk->url.'/data.json';

    if ($res->location =~ m{(https?://([^\./]+)\.itch\.io\/([^\./]+))/data\.json}) {
        $lnk->save(dead => 1, price => undef, detail => { location => $1 });
        return $task->done('dead: redirect to %s/%s', $2, $3);
    }

    $res->expect(200);
    my $json = $res->json;
    $res->dead($json->{errors}[0]) if $json->{errors};

    # Unclear whether Itch supports pages for games that can't be downloaded.
    # 'price' field can be missing for free games, API response does not list downloadables.
    my $price = !$json->{price} || $json->{price} eq '$0.00' ? 'free' : $json->{price} =~ s/^\$/US\$ /r;

    $lnk->save(price => $price, detail => {
        title => $json->{title},
        id => $json->{id},
        authors => [ map $_->{name}, $json->{authors}->@* ],
    });
    $task->done('%s', $price);
}

el_queue 'el/itchio',
    freq   => '30d',
    triage => sub($lnk) { $lnk->site eq 'itch' },
    \&fetch;

1;
