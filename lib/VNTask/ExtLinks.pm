package VNTask::ExtLinks;

use v5.36;
use VNTask::Core;
use VNDB::ExtLinks '%LINKS';
use FU::SQL;
use Exporter 'import';

our @EXPORT = ('config', 'el_queue', 'http_get', '%LINKS');

# Register an ExtLink queue handler, usage:
#
#   el_queue 'el/queue-name',
#       %{task() options},
#       freq   => Update frequency for each link (delay between updates)
#       triage => sub{$lnk} { return true if $lnk belongs to this queue }
#       batch  => $n,  # Number of links to fetch in one run, default 1
#       sub($task, @links) {
#       ..
#       $_->save(...) for @links;
#   };
#
our %queues;
sub el_queue {
    my $id = shift;
    my $sub = pop;
    $queues{$id} = { batch => 1, freq => '90d', @_, fetch => $sub, id => $id };
}


sub grablinks($task, $batch) {
    my $lst = $task->SQL('
        SELECT id, site, value, data, price, queue, lastfetch
          FROM extlinks
         WHERE ', $task->arg ? ('id =', $task->arg) : ('queue =', $task->id, 'AND nextfetch < NOW()'), '
         ORDER BY nextfetch LIMIT', $batch,
    )->allh;
    for (@$lst) {
        $_ = bless $_, 'VNTask::ExtLinks::Link';
        $_->{task} = $task;
    }
    # The current task can be delayed or disabled depending on the next item in the queue.
    # (This SQL is executed after the task has completed)
    $task->{nextrun} = SQL '(SELECT nextfetch FROM extlinks WHERE queue =', $task->id, 'ORDER BY nextfetch LIMIT 1)';
    $lst;
}


return 1 if !config->{extlink_fetcher};

# The 'el-triage' task looks for new (or recently re-referenced) tasks and
# assigns them to the proper queue.
# This can totally be done entirely within SQL, but going through this Perl
# code gives us more flexibility and allows for changing parameters without
# fiddling with DB update queries.
# TODO: This task can also be used to verify and normalize links according to
# the VNDB::ExtLinks rules, but that's only relevant when those have changed.
task 'el-triage', delay => '30s', sub($task) {
    my $lst = grablinks $task, 500;
    for my $lnk (@$lst) {
        my $q = $lnk->triage;
        task_insert $task->{txn}, $q->{id}, nextrun => $task->arg ? time : $lnk->nextfetch(), map +($_, $q->{$_}), qw/delay align_div align_add/ if $q;
        $lnk->save(didnotfetch => 1);
    }
    $task->done('%d links', scalar @$lst);
};


# TODO: Task to periodically check the 'tasks' table for 'el/*' rows and
# disable ones that don't have any extlinks queued or dynamically adjust the
# delay based on configured freq & number of links.


task qr{el/.+}, sub($task) {
    my $queue = $queues{ $task->id };
    if (!$queue) {
        warn "ERROR: No EL queue handler found.\n";
        $task->{nextfetch} = undef;
        return;
    }
    my $lst = grablinks $task, $queue->{batch};
    return $task->done('nothing to do') if !@$lst;

    # Batch fetching needs its own error handling
    return $queue->{fetch}->($task, @$lst) if $queue->{batch} > 1;

    # For single-link fetches, we catch errors and update the link state.
    my($lnk) = @$lst;
    $task->item($lnk->{value});
    return if eval {
        $queue->{fetch}->($task, $lnk);
        1;
    };
    my($msg, $detail) = ($@);
    if (ref $@ eq 'VNTask::Core::HTTPResponse') {
        $msg = $@->{ErrorMsg};
        $detail = {
            error => $msg,
            !$@->{Dead}  ? (unrecognized => !!1         ) : (),
            $@->code     ? (code         => $@->code    ) : (),
            $@->location ? (location     => $@->location) : (),
        };
    }
    $lnk->save(dead => 1, price => undef, detail => $detail);
    $task->done("%s: %s", $detail && !$detail->{unrecognized} ? 'dead' : 'ERROR', $msg);
};


package VNTask::ExtLinks::Link;

use v5.36;
use List::Util 'first';
use FU::SQL;

sub id { $_[0]{id} }
sub site { $_[0]{site} }
sub value { $_[0]{value} }
sub data { $_[0]{data} }
sub url($s, $data=undef) { VNDB::ExtLinks::extlink_fmt($s->{site}, $s->{value}, $data//$s->data//'') }

sub triage($l) {
    $l->{triage} ||= first { $_->{triage}->($l) } values %VNTask::ExtLinks::queues;
}

sub nextfetch($l) {
    return undef if !$l->triage;
    $l->{lastfetch} ? $l->{lastfetch} + VNTask::Core::interval2seconds($l->triage->{freq}) : time - 365*24*3600
}

sub save($l, %opt) {
    $l->{lastfetch} = time if !$opt{didnotfetch};
    my $q = $l->triage;

    $opt{detail} = undef if ref $opt{detail} eq 'HASH' && !keys $opt{detail}->%*;
    my $d = $opt{detail} || {};

    $l->{task}->SQL('UPDATE extlinks', SET({
        queue     => $q ? SQL('CASE WHEN c_ref THEN', $q->{id}, 'ELSE NULL END') : undef,
        nextfetch => SQL('CASE WHEN c_ref THEN', $l->nextfetch(), '::timestamptz ELSE NULL END'),
        lastfetch => $l->{lastfetch},
        $opt{didnotfetch} ? () : (
            deadsince    => $opt{dead} ? SQL 'COALESCE(deadsince, NOW())' : undef,
            deadcount    => $opt{dead} ? SQL 'COALESCE(deadcount, 0)+1' : undef,
            redirect     => exists $d->{location},
            unrecognized => !!$d->{unregonized},
            serverror    => !!($d->{code} && $d->{code} >= 500),
            map exists($opt{$_}) ? ($_, $opt{$_}) : (), qw/data price/,
        ),
    }), 'WHERE id =', $l->{id})->exec;

    $l->{task}->SQL('INSERT INTO extlinks_fetch', VALUES {
        id     => $l->{id},
        dead   => !!$opt{dead},
        data   => exists $opt{data}  ? $opt{data}  : $l->{data},
        price  => exists $opt{price} ? $opt{price} : $l->{price},
        detail => $opt{detail},
    })->exec if !$opt{didnotfetch};
}

1;
