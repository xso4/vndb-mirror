package VNTask::HIBP;

# This downloads and maintains a full copy of the Have I Been Pwned SHA1
# database using their range API.
# -> https://haveibeenpwned.com/API/v3#PwnedPasswords
#
# Output database format:
#   $VNDB_VAR/hibp/####  -> file for hashes prefixed with those two bytes
#
#   Each file is an ordered concatenation of raw hashes, excluding the first
#   two bytes (part of the filename) and the last 8 bytes (truncated hashes),
#   so each hash is represented with 10 bytes.
#
#   This means we actually store 96bit truncated SHA1 hashes, which should
#   still provide a very low probability of collision. A bloom filter may have
#   a lower collision probability for the same amount of space, but is also
#   more complex and expensive to manage.
#
# CLI usage:
#
#   hibp            # fetch next file
#   hibp $filename  # fetch specific file (4-char hex)

use v5.36;
use VNTask::Core;
use LWP::UserAgent;

my $api = 'https://api.pwnedpasswords.com/range/';
my $dir = config->{var_path}.'/hibp';

# 65536 files to fetch with a 2 minute delay -> ~91 days for a full refresh.
task hibp => delay => '2m', sub($task) {
    mkdir $dir;
    my $num = $task->data->{next} // 0;
    if ($task->arg) {
        die "Invalid argument: ".$task->arg."\n" if $task->arg !~ /^([a-fA-F0-9]{4})$/;
        $num = hex $task->arg;
    }
    $task->item(sprintf '%04X', $num);

    my $ua = LWP::UserAgent->new(
        timeout      => 60,
        max_redirect => 0,
        keep_alive   => 1,
        max_size     => 1024*1024,
        agent        => 'VNDB.org HIBP fetcher ('.config->{admin_email}.')'
    );

    my($data, $count) = ('', 0);
    for my $n (0..15) {
        my $uri = sprintf '%s%04X%X', $api, $num, $n;
        my $res = $ua->get($uri);
        die sprintf "Error status for %s: %s\n", $uri, $res->status_line if !$res->is_success;
        die "Error fetching $uri: Client aborted\n" if $res->header('Client-Aborted');
        my $body = $res->decoded_content(raise_error => 1);

        for (split /\r?\n/, $body) {
            # 40-5 -> 35 hex chars per hash; 16 of which we discard so 19 we grab.
            warn "Unrecognized line in $uri: $_\n" if !/^([a-fA-F0-9]{19})[a-fA-F0-9]{16}:[0-9]+$/;
            $count++;
            $data .= pack 'H*', $n.$1;
        }
    }

    my $file = sprintf '%s/%04X', $dir, $num;
    my $old = (-s $file) // 0;
    {
        open my $OUT, '>', "$file~" or die $!;
        print $OUT $data;
    }
    rename "$file~", $file or die $!;
    warn sprintf "%d hashes, %.0f -> %.0f KiB\n", $count, $old/1024, length($data)/1024;

    $task->data->{next} = $num >= 0xffff ? 0 : $num+1 if !defined $task->arg;
};

1;
