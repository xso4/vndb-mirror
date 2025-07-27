package VNTask::Core;

use v5.36;
use VNDB::Config;
use FU::Pg;
use FU::SQL;
use FU::Log;
use Time::HiRes 'time';
use List::Util 'first';
use Carp 'confess';
use POSIX 'fmod';
use LWP::UserAgent;
use LWP::ConnCache;
use Exporter 'import';

our @EXPORT = ('task', 'task_insert', 'config', 'http_get');


our $cur_task;
FU::Log::capture_warn(1);
FU::Log::set_file(config->{task_logfile}) if config->{task_logfile};
FU::Log::set_fmt(sub($msg) {
    FU::Log::default_fmt($msg, $$, $cur_task ? "[$cur_task->{id}".($cur_task->{item}?" $cur_task->{item}":'').']' : '[global]');
});


# All intervals used within VNTask are essentially just a fancy wrapper around
# 'positive seconds'. This makes it easy to calculate time offets and such, but
# doesn't support the full range or functionality of the Postgres interval type.
sub interval2seconds($s) {
    local $_ = $s;
    my $v = 0;
    $v += $1 * 24*3600 if s/^\s*([0-9]+)\s*(?:d|days?)\s*//;
    if (s/^\s*([0-9]+):([0-9]+)(?::([0-9]+(?:\.[0-9]+)?))?\s*//) {
        $v += ($1 * 3600) + ($2 * 60) + ($3 // 0);
    } else {
        $v += $1 * 3600 if s/^\s*([0-9]+)\s*(?:h|hours?)\s*//;
        $v += $1 * 60 if s/^\s*([0-9]+)\s*(?:m|mins?|minutes?)\s*//;
        $v += $1 if s/^\s*([0-9]+(?:\.[0-9]+)?)\s*(?:s|secs?|seconds?)?\s*//;
    }
    confess "Unrecognized interval format '$s'" if length $_;
    $v
}


my %sqltrace;
sub db { state $db = do {
    my $db = FU::Pg->connect(config->{db_task}//'');
    $db->set_type(interval =>
        send => sub($s) {
            my $v = interval2seconds($s);
            pack 'q>NN', int(fmod($v, 24*3600) * 1000_000), int($v / 24 / 3600), 0
        },
        recv => sub($b) {
            my($time, $day, $mon) = unpack 'q>NN', $b;
            confess "Can't deal with interval values containing 'month' numbers" if $mon;
            ($time / 1000_000) + ($day * 24 * 3600)
        },
    );
    $db->exec('SET timezone=UTC');
    $db->query_trace(sub($st,@) {
        $sqltrace{n}++;
        $sqltrace{t} += $st->exec_time + ($st->prepare_time||0);
        #warn sprintf "%f  %s\n", $st->exec_time, $st->query;
    });
    $db;
} }


sub task_insert($txn, $name, %opt) {
    $txn->Q(
        'INSERT INTO tasks', VALUES({
            id        => $name,
            nextrun   => exists $opt{nextrun} ? $opt{nextrun} : SQL('NOW()'),
            delay     => $opt{delay},
            align_div => $opt{align_div},
            align_add => $opt{align_add},
        }),
        'ON CONFLICT (id) DO UPDATE SET
            delay     = EXCLUDED.delay,
            align_div = EXCLUDED.align_div,
            align_add = EXCLUDED.align_add,
            nextrun   = ', exists $opt{nextrun} ? 'LEAST(tasks.nextrun, excluded.nextrun)' : 'COALESCE(tasks.nextrun, NOW())', '
         WHERE tasks.delay     IS DISTINCT FROM excluded.delay
            OR tasks.align_div IS DISTINCT FROM excluded.align_div
            OR tasks.align_add IS DISTINCT FROM excluded.align_add
            OR tasks.nextrun   IS NULL',
            exists $opt{nextrun} ? 'OR tasks.nextrun > excluded.nextrun' : (),
    )->exec;
}

my(%tasks, @re_tasks);

# Register a task:
#   task queuename => %opts, sub($task) {
#       ...
#   }
sub task {
    my $name = shift;
    my $sub = pop;
    my %opt = @_;
    if (ref $name) {
        die "No options supported for regexp tasks ($name)\n" if keys %opt;
        push @re_tasks, [ $name, $sub ];
    } else {
        $tasks{$name} = $sub;
        task_insert db, $name, %opt;
    }
}


sub run_task($txn, $task) {
    my $start = time;

    bless $task, 'VNTask::Core::Task';
    $task->item('');
    local $cur_task = $task;

    my $sub = $tasks{$task->{id}};
    if (!$sub) {
        $sub = first { $task->{id} =~ /^$_->[0]$/ } @re_tasks;
        $sub &&= $sub->[1];
    }
    if (!$sub) {
        warn "ERROR: Task '$task->{id}' has no implementation or has been disabled.\n";
        $txn->q('UPDATE tasks SET nextrun = NULL WHERE id = $1', $task->{id})->exec;
        $txn->commit;
        return;
    }

    $task->{txn} = $txn->txn;
    $task->{nextrun} = time;
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
            nextrun => $task->{nextrun},
            $ok ? (data => $task->{data}) : (),
        }), 'WHERE id =', $task->{id},
        "RETURNING date_trunc('seconds', (sched-NOW()))::text"
    )->val;
    $txn->commit;
    warn sprintf "%.0fms (%.0fms %dq)%s%s\n",
        (time-$start)*1000,
        ($sqltrace{t}||0)*1000, $sqltrace{n}||0,
        $nextrun ? ', next in '.($nextrun =~ s/ days? /d/r) : '',
        $task->{done} ? " # $task->{done}" : '';
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
        protocols_allowed => ['http', 'https'],
    );
    my $res = $lwp->get($uri);

    my $body = $res->decoded_content;
    my($code, $reason) =
        $res->header('Client-Aborted') ? (600, 'Client aborted') :
        $res->header('X-Died') ? (600, 'Died') :
        $res->header('Client-Warning') && $res->header('Client-Warning') !~ /^Redirect loop/ ? (600, $res->message) :
        !defined $body ? (600, 'Error decoding body') :
        ($res->code, $res->message);

    my %hdr;
    for my ($k,$v) ($res->headers->flatten) {
        push $hdr{lc $k}->@*, $v;
    }

    warn "GET $uri\n$code $reason\n".join('', map "$_: ".join(', ', $hdr{$_}->@*)."\n", sort keys %hdr)."\n".$body
        if $ENV{VNTASK_DEBUG_HTTP};

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

sub id { $_[0]{id} }

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
