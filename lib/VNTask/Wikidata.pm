package VNTask::Wikidata;

use v5.36;
use VNTask::Core;
use VNDB::ExtLinks ();
use FU::SQL;
use FU::Util 'json_parse';

return 1 if !config->{wikidata_fetcher};

my $api = 'https://www.wikidata.org/w/api.php';
my $fetch_num = 50;  # Maximum number of entries to fetch in a single API call
my $fetch_target = '1d'; # Minimum delay between fetching the same entry

# property_id -> column name
my %props =
    map +($VNDB::ExtLinks::WIKIDATA{$_}{property}, $_),
    grep $VNDB::ExtLinks::WIKIDATA{$_}{property}, keys %VNDB::ExtLinks::WIKIDATA;


sub entity($task, $id, $data, $n, $upd) {
    $task->item("Q$id");
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
        'INSERT INTO wikidata', VALUES({ id => $id, %set }),
        'ON CONFLICT (id) DO UPDATE', SET(\%set),
        'WHERE', OR(map RAW("wikidata.$_ IS DISTINCT FROM EXCLUDED.$_"), sort keys %set)
    )->exec;
    $task->sql(q{UPDATE extlinks SET lastfetch = NOW(), deadsince = NULL WHERE site = 'wikidata' AND value = $1}, $id)->exec;
}


task wikidata => delay => '5m', sub($task) {
    my $lst = $task->arg ? [map s/^Q//r, split /,/, $task->arg] : $task->sql("
        SELECT value FROM extlinks
         WHERE site = 'wikidata' AND c_ref
           AND (lastfetch IS NULL OR lastfetch < now() - interval '$fetch_target')
         ORDER BY lastfetch NULLS FIRST
         LIMIT $fetch_num
    ")->flat;
    return if !@$lst;

    my $uri = "$api?action=wbgetentities&format=json&props=sitelinks|claims&sitefilter=enwiki|jawiki&ids="
        .join '|', map "Q$_", @$lst;

    my $res = http_get $uri, task => 'Wikidata Fetcher';
    die "Unexpected API response: $res->{Status} $res->{Reason}\n" if $res->{Status} != 200;
    my $data = eval { json_parse $res->{Body}, utf8 => 1 } || die "Invalid JSON: $res->{Body}\n";

    # Unfortunately, if even a single ID does not exist, the entire response is
    # an error for just that ID. Best we can do is mark it as dead and let the
    # other IDs get re-fetched next time.
    my $err = $data->{error};
    if ($err && $err->{id}) {
        $task->sql(q{UPDATE extlinks SET lastfetch = NOW(), deadsince = NOW() WHERE site = 'wikidata' AND value = $1}, $err->{id} =~ s/^Q//r)->exec;
        warn +($err->{info} || "$err->{id}: $err->{code}")."\n";
        return;
    }
    # Other error?
    die "$err->{info}\n" if $err;

    my($n,$upd);
    entity $task, $_, $data->{entities}{"Q$_"}, \$n, \$upd for @$lst;
    $task->item;
    $task->done('%d/%d updated, %d properties', $upd, scalar @$lst, $n);
};

1;
