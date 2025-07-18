package VNTask::Core;

use v5.36;
use VNDB::Config;
use FU::Pg;
use FU::SQL;
use FU::Log;
use Time::HiRes 'time';
use POSIX 'strftime';
use Exporter 'import';

our @EXPORT = ('task', 'config');


our $cur_task;
FU::Log::capture_warn(1);
FU::Log::set_file(config->{task_logfile}) if config->{task_logfile};
FU::Log::set_fmt(sub($msg) {
    FU::Log::default_fmt($msg, $cur_task ? "[$cur_task->{id}".($cur_task->{item}?" $cur_task->{item}":'').']' : '[global]');
});


sub db { state $db = do {
    my $db = FU::Pg->connect(config->{db_task}//'');
    $db->exec('SET timezone=UTC');
    $db;
} }


my %tasks;

# Register a task:
#   task queuename => %opts, sub($task) {
#       ...
#   }
sub task {
    my $name = shift;
    my $sub = pop;
    my %opt = @_;
    $tasks{$name} = $sub;

    db->Q(
        'INSERT INTO tasks', VALUES({
            id        => $name,
            nextrun   => SQL('NOW()'),
            delay     => $opt{delay},
            align_div => $opt{align_div},
            align_add => $opt{align_add},
        }),
        'ON CONFLICT (id) DO UPDATE SET
            delay     = EXCLUDED.delay,
            align_div = EXCLUDED.align_div,
            align_add = EXCLUDED.align_add
         WHERE tasks.delay     IS DISTINCT FROM excluded.delay
            OR tasks.align_div IS DISTINCT FROM excluded.align_div
            OR tasks.align_add IS DISTINCT FROM excluded.align_add'
    )->text_params->exec;
}


sub run_task($txn, $task) {
    my $start = time;

    bless $task, 'VNTask::Core::Task';
    $task->item('');
    local $cur_task = $task;

    my $sub = $tasks{$task->{id}};
    if (!$sub) {
        warn "Task '$task->{id}' has no implementation or has been disabled.\n";
        $txn->q('UPDATE tasks SET nextrun = NULL WHERE id = $1', $task->{id})->exec;
        $txn->commit;
        return;
    }

    $task->{txn} = $txn->txn;
    my $ok = eval {
        $sub->($task);
        $task->{txn}->commit;
        1;
    };
    if (!$ok) {
        $task->{txn}->rollback;
        warn "ERROR: $@";
    }
    undef $task->{txn};

    $task->{data} = undef if $task->{data} && !keys $task->{data}->%*;

    my $nextrun = $txn->Q('UPDATE tasks', SET({
        lastrun => SQL('NOW()'),
        nextrun => SQL('NOW()'), # Should be set by the task
        $ok ? (data => $task->{data}) : (),
    }), 'WHERE id =', $task->{id}, 'RETURNING sched')->val;
    warn sprintf "Task completed in %.1fms, next @ %sZ\n", (time-$start)*1000, strftime '%Y-%m-%d %H:%M:%S', gmtime $nextrun;
    $txn->commit;
}


sub loop {
    while (1) {
        $0 = 'vntask idle';
        my $txn = db->txn;
        my $task = $txn->q('SELECT id, data FROM tasks WHERE sched <= NOW() ORDER BY sched LIMIT 1 FOR UPDATE SKIP LOCKED')->rowh;
        if (!$task) {
            undef $txn;
            # Yup, just poll every few sec.
            # We Could use LISTEN/NOTIFY to be more responsive to database
            # changes, but none of the current tasks require low-ish latency,
            # so this is simpler and works fine.
            sleep 3;
        } else {
            run_task $txn, $task;
        }
    }
}


sub one($name, $arg=undef) {
    my $txn = db->txn;
    my $task = $txn->q('SELECT id, data FROM tasks WHERE id = $1 FOR UPDATE', $name)->rowh;
    die "Unknown task '$name'\n" if !$task;
    $task->{arg} = $arg;
    run_task $txn, $task;
}


package VNTask::Core::Task;

use v5.36;

sub sql { $_[0]{txn}->q(@_) }
sub SQL { $_[0]{txn}->Q(@_) }

# CLI argument when called from the CLI, otherwise undef.
sub arg { $_[0]{arg} }

# Current item being processed, used for logging and monitoring
sub item { $_[0]{item} = $_[1]; $0 = "vntask $_[0]{id} $_[1]" }

# JSON data associated with the queue,
# modifications are saved to the database when ->done is called.
sub data { $_[0]{data} ||= {} }

1;
