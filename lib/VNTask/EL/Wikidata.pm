package VNTask::EL::Wikidata;

use v5.36;
use VNTask::ExtLinks;
use FU::SQL;

my $api = 'https://www.wikidata.org/w/api.php';

# property_id -> column name
my %props =
    map +($VNDB::ExtLinks::WIKIDATA{$_}{property}, $_),
    grep $VNDB::ExtLinks::WIKIDATA{$_}{property}, keys %VNDB::ExtLinks::WIKIDATA;


sub entity($task, $lnk, $data, $n, $upd) {
    return $lnk->save(dead => 1) if exists $data->{missing};

    $task->item('Q'.$lnk->{value});
    my %set = (
        enwiki => $data->{sitelinks}{enwiki}{title},
        jawiki => $data->{sitelinks}{jawiki}{title},
    );
    for my($p, $col) (%props) {
        for my $claim ($data->{claims}{$p}->@*) {
            if ($claim->{qualifiers}{P582} || $claim->{qualifiers}{P8554}) {
                # We don't keep values with an 'end time'
                next;
            }
            my $v = $claim->{mainsnak}{datavalue}{value};
            if (ref $v) {
                warn "Non-scalar value for '$col'\n";
                next;
            }
            push $set{$col}->@*, $v if defined $v;
        }
    }
    $$n += grep $_, values %set;
    $set{$_} ||= undef for values %props;

    $$upd += $task->SQL(
        'INSERT INTO wikidata', VALUES({ id => $lnk->{value}, %set }),
        'ON CONFLICT (id) DO UPDATE', SET(\%set),
        'WHERE', OR(map RAW("wikidata.$_ IS DISTINCT FROM EXCLUDED.$_"), sort keys %set)
    )->exec;

    $lnk->save(detail => {
        $data->{labels}{en}       ? (label       => $data->{labels}{en}{value}      ) : (),
        $data->{descriptions}{en} ? (description => $data->{descriptions}{en}{value}) : (),
    });
}


sub fetch($task, @links) {
    my $uri = "$api?action=wbgetentities&format=json&props=sitelinks|claims|labels|descriptions&languages=en&sitefilter=enwiki|jawiki&ids="
        .join '|', map "Q$_->{value}", @links;

    my $res = http_get $uri, task => 'Wikidata Fetcher';
    $res->expect(200);
    my $data = $res->json;

    # An invalid ID can cause the entire response to be an error for that ID.
    my $err = $data->{error};
    if ($err && $err->{id}) {
        my $id = $err->{id} =~ s/^Q//r;
        $_->save(dead => 1) for grep $_->value eq $id, @links;
        warn +($err->{info} || "$err->{id}: $err->{code}")."\n";
        return;
    }
    # Other error?
    die "$err->{info}\n" if $err;

    my($n,$upd) = (0,0);
    entity $task, $_, $data->{entities}{'Q'.$_->value}, \$n, \$upd for @links;
    $task->item;
    $task->done('%d/%d updated, %d properties', $upd, scalar @links, $n);
}


el_queue 'el/wikidata',
    delay  => '5m',
    batch  => 50,
    freq   => '1d',
    triage => sub($lnk) { $lnk->site eq 'wikidata' },
    \&fetch;

1;
