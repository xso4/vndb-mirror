package VNTask::ExtLinks;

use v5.36;
use VNTask::Core;
use FU::SQL;
use Exporter 'import';

our @EXPORT = ('el_queue');

# Register an ExtLink queue handler, usage:
#
#   el_queue 'el/queue-name',
#       %{task() options},
#       freq   => Update frequency for each link (delay between updates)
#       triage => sub{$lnk} { return true if $lnk belongs to this queue }
#       batch  => $n,  # Number of links to fetch in one run, default 1
#       sub($task, @links) {
#       ..
#       $_->done(...) for @links;
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
        SELECT id, site, value, queue, lastfetch
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

    # TODO: Not relevant yet, but it may be worth re-triaging fetched links
    # before fetching them, to ensure they're still in the right queue and
    # properly normalized.
    if (@$lst) {
        $task->item($lst->[0]{value}) if $queue->{batch} == 1;
        $queue->{fetch}->($task, @$lst);
    }
};


package VNTask::ExtLinks::Link;

use v5.36;
use List::Util 'first';
use FU::SQL;

sub id { $_[0]{id} }
sub site { $_[0]{site} }
sub value { $_[0]{value} }

sub triage($l) {
    $l->{triage} ||= first { $_->{triage}->($l) } values %VNTask::ExtLinks::queues;
}

sub nextfetch($l) {
    return undef if !$l->triage;
    $l->{lastfetch} ? $l->{lastfetch} + VNTask::Core::interval2seconds($l->triage->{freq}) : time
}

sub save($l, %opt) {
    $l->{lastfetch} = time if !$opt{didnotfetch};
    my $q = $l->triage;
    my %set = (
        queue     => $q ? $q->{id} : undef,
        lastfetch => $l->{lastfetch},
        nextfetch => $l->nextfetch(),
        $opt{didnotfetch} ? () : (deadsince => $opt{dead} ? SQL 'COALESCE(deadsince, NOW())' : undef),
    );
    $l->{task}->SQL('UPDATE extlinks', SET(\%set), 'WHERE id =', $l->{id})->exec;
}

1;
