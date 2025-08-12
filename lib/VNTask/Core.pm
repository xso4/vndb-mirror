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
use Digest::SHA 'sha1_hex';
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


# Wrapper around curl. Usage:
#
#   my $res = http_get $uri, %opt;
#   OR:
#   my ($a, $b) = http_get [$uri_a, $uri_b], %opt;
#
#   $res->expect(200); # throw error if code isn't 200
#   $res->code; # response code
#   $res->body; # raw data
#   $res->text; # decoded character data (assumes body is UTF-8, for now)
#   $res->json; # decoded JSON
#
# All methods throw on error.
#
# While I'm not a fan of shelling out and writing to the filesystem just to do
# HTTP requests, this approach does have some advantages over using
# LWP::UserAgent or similar. For one, LWP::UserAgent mangles client headers
# into the response object and tries to be too clever with respect to content
# decoding, in ways that aren't always useful. Curl also has the advantage of
# being a more common dependency, more actively maintained and having a ton of
# options that may be useful down the road (proxying, certificate inspection,
# etc). Using the filesystem happens to simplify caching and debugging.
sub http_get($uri, %opt) {
    my $path = config->{var_path}.'/tmp/task-http';
    mkdir $path;
    my @uri = ref $uri ? @$uri : ($uri);
    my $fn = substr($uri[0] =~ s{^https?://}{}r =~ s/[^a-zA-Z0-9_.-]+/-/rg, 0, 80).'-'.substr(sha1_hex(join "\n", @uri), 0, 8);

    my @resp = map +{
        ExitCode => -1,
        Code => 0,
        ErrorMsg => 'failed to run curl',
        Uri => $uri[$_],
        Index => $_,
        Path => "$path/$fn"
    }, 0..$#uri;

    no warnings 'qw';
    system('curl',
       qw/--silent --fail-early --globoff --include --compressed --proto =http,https --max-time 60 --max-filesize 10M/,
       '-w', '%output{>>'.$path.'/'.$fn.'}%{exitcode} %{response_code} %{errormsg}%{redirect_url}\n',
       '--user-agent', sprintf('VNDB.org %s (%s)', delete($opt{task})||'link checker', config->{admin_email}),
       map +($_->{Uri}, '-o', "$_->{Path}-$_->{Index}"), @resp
    ) if !-f "$path/$fn";

    bless($_, 'VNTask::Core::HTTPResponse')->_read for @resp;
    @resp == 1 ? $resp[0] : @resp
}


package VNTask::Core::HTTPResponse;

use v5.36;
use overload '""' => sub($r,@) { "$r->{Uri}: ". ($r->{ErrorMsg} || "Unexpected response ($r->{Code})")."\n" };
use FU::Util 'json_parse';

sub _read($r) {
    local $_;
    {
        open my $F, '<', $r->{Path} or die "Unable to read $r->{Path}: $!\n";
        my $i = 0;
        while (<$F>) {
            next if $i++ != $r->{Index};
            chomp;
            ($r->{ExitCode}, $r->{Code}, $r->{ErrorMsg}) = split / /, $_, 3;
            ($r->{Location}, $r->{ErrorMsg}) = ($r->{ErrorMsg}, '') if $r->{ExitCode} == 0 && $r->{Code} =~ /^3/;
            last;
        }
    }
    die $r if $r->{ExitCode};

    my $fn = "$r->{Path}-$r->{Index}";
    open my $F, '<', $fn or die "Unable to read $fn: $!\n";
    scalar <$F>; # First line is protocol + status code; ignore
    while (<$F>) {
        s/\r?\n$//;
        last if !/^([^:\s]+)\s*:\s*(.+)$/;
        my($k, $v) = (lc $1, $2);
        $r->{$k} = length $r->{$k} ? "$r->{$k}; $v" : $v;
    }
    local $/ = undef;
    $r->{Body} = <$F>;
}

# Throw an error with the request object as context.
sub err($r, $msg) { $r->{ErrorMsg} = $msg; die $r; }

# Same as err() but also sets a flag. Used by ExtLinks.pm to mark the link as
# dead without logging a critical error. So err() is for when we get an
# unexpected response that may need investigation, dead() for an
# expected-but-confirmed-dead response.
sub dead($r, $msg) { $r->{Dead} = 1; $r->err($msg); }

sub expect($r, $code) {
    $r->err("Unexpected status code: $r->{Code}".($r->{Location} ? " $r->{Location}" : ''))
        if $r->{Code} !~ /^(?:$code)/;
}

sub code($r) { $r->{Code} }
sub location($r) { $r->{Location}||'' }
sub body($r) { $r->{Body} }
sub text($r) {
    $r->err("Invalid UTF-8") if !utf8::decode(my $v = $r->{Body});
    $v;
}
sub json($r) {
    eval { json_parse $r->{Body}, utf8 => 1 } || $r->err("Invalid JSON")
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
