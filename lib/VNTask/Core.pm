package VNTask::Core;

use v5.36;
use VNDB::Config;
use FU::Pg;
use FU::SQL;
use FU::Log;
use Time::HiRes 'time';
use LWP::UserAgent;
use LWP::ConnCache;
use Exporter 'import';

our @EXPORT = ('task', 'config', 'http_get');


our $cur_task;
FU::Log::capture_warn(1);
FU::Log::set_file(config->{task_logfile}) if config->{task_logfile};
FU::Log::set_fmt(sub($msg) {
    FU::Log::default_fmt($msg, $$, $cur_task ? "[$cur_task->{id}".($cur_task->{item}?" $cur_task->{item}":'').']' : '[global]');
});


my %sqltrace;
sub db { state $db = do {
    my $db = FU::Pg->connect(config->{db_task}//'');
    $db->exec('SET timezone=UTC');
    $db->query_trace(sub($st,@) {
        $sqltrace{n}++;
        $sqltrace{t} += $st->exec_time + ($st->prepare_time||0);
    });
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
            align_add = EXCLUDED.align_add,
            nextrun   = COALESCE(tasks.nextrun, NOW())
         WHERE tasks.delay     IS DISTINCT FROM excluded.delay
            OR tasks.align_div IS DISTINCT FROM excluded.align_div
            OR tasks.align_add IS DISTINCT FROM excluded.align_add
            OR tasks.nextrun   IS NULL'
    )->text_params->exec;
}


sub run_task($txn, $task) {
    my $start = time;

    bless $task, 'VNTask::Core::Task';
    $task->item('');
    local $cur_task = $task;

    my $sub = $tasks{$task->{id}};
    if (!$sub) {
        warn "ERROR: Task '$task->{id}' has no implementation or has been disabled.\n";
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

    my $nextrun = $txn->Q('
        UPDATE tasks',
        SET({
            lastrun => SQL('NOW()'),
            nextrun => SQL('NOW()'), # Should be set by the task
            $ok ? (data => $task->{data}) : (),
        }), 'WHERE id =', $task->{id},
        "RETURNING date_trunc('seconds', (sched-NOW()))::text"
    )->val;
    $txn->commit;
    warn sprintf "%.0fms (%.0fms %dq), next in %s%s\n",
        (time-$start)*1000,
        ($sqltrace{t}||0)*1000, $sqltrace{n}||0,
        $nextrun =~ s/ days? /d/r,
        $task->{done} ? "; $task->{done}" : '';
}


sub loop {
    my $prog = $0;
    my $restart;
    $SIG{HUP} = sub { $restart = 1 };

    while (1) {
        exec $^X, $prog if $restart;
        $0 = 'vndb-task: idle';

        my $txn = db->txn;
        %sqltrace = ();
        my $task = $txn->q('SELECT id, data FROM tasks WHERE sched <= NOW() ORDER BY sched LIMIT 1 FOR UPDATE SKIP LOCKED')->rowh;
        if (!$task) {
            undef $txn;
            # Yup, just poll every few sec.
            # We Could use LISTEN/NOTIFY to be more responsive to database
            # changes, but none of the current tasks require low-ish latency,
            # so this is simpler and works fine.
            sleep 5;
        } else {
            run_task $txn, $task;
        }
    }
}


sub one($name, $arg=undef) {
    my $txn = db->txn;
    %sqltrace = ();
    my $task = $txn->q('SELECT id, data FROM tasks WHERE id = $1 FOR UPDATE', $name)->rowh;
    die "Unknown task '$name'\n" if !$task;
    $task->{arg} = $arg;
    run_task $txn, $task;
}


# Simple wrapper around LWP for GET requests, with some inspiration from
# AnyEvent::HTTP.
# Doesn't follow redirects, returns an object with:
# {
#     Status => $code || 6xx on internal error
#     Reason => $status_line || internal error message
#     Body => Decoded body || '' on error
#     Obj => HTTP::Response object
#     %lowercase_response_headers
# }
sub http_get($uri, %opt) {
    my $lwp = LWP::UserAgent->new(
        timeout      => 60,
        max_redirect => 0,
        max_size     => 10*1024*1024,
        conn_cache   => $cur_task && ($cur_task->{lwpcache} ||= LWP::ConnCache->new(total_capacity => 5)),
        from         => config->{admin_email},
        agent        => sprintf('VNDB.org %s (%s)', delete($opt{task})||'Task Processor', config->{admin_email}),
    );
    my $res = $lwp->get($uri);

    my $body = $res->decoded_content;
    my($code, $reason) =
        $res->header('Client-Aborted') ? (600, 'Client aborted') :
        $res->header('X-Died') ? (600, 'Died') :
        $res->header('Client-Warning') ? (600, $res->message) :
        !defined $body ? (600, 'Error decoding body') :
        ($res->code, $res->message);

    my %hdr;
    for my ($k,$v) ($res->headers->flatten) {
        push $hdr{lc $k}->@*, $v;
    }

    +{
        (map +($_, join ', ', $hdr{$_}->@*), keys %hdr),
        Status => $code,
        Reason => $reason,
        Body => $body // '',
        Obj => $res,
    }
}

package VNTask::Core::Task;

use v5.36;

sub exec {shift->{txn}->exec(@_) }
sub sql { shift->{txn}->q(@_) }
sub SQL { shift->{txn}->Q(@_) }

# CLI argument when called from the CLI, otherwise undef.
sub arg { $_[0]{arg} }

# Current item being processed, used for logging and monitoring
sub item { $_[0]{item} = $_[1]||''; $0 = "vndb-task: $_[0]{id} $_[0]{item}" }

# JSON data associated with the queue,
# modifications are saved to the database when ->done is called.
sub data { $_[0]{data} ||= {} }

# Append a status string to the final log message for this task.
sub done { $_[0]{done} = @_ > 2 ? sprintf($_[1], @_[2..$#_]) : $_[1] }

1;
