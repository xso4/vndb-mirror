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

return 1 if !config->{hibp_download};

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

    my($data, $count) = ('', 0);
    my @res = http_get [map sprintf('%s%04X%X', $api, $num, $_), 0..15 ], task => 'HIBP Fetcher';
    for my ($n, $res) (builtin::indexed(@res)) {
        $res->expect(200);
        $res->err("Empty response") if !length $res->body;
        for (split /\r?\n/, $res->{Body}) {
            # 40-5 -> 35 hex chars per hash; 16 of which we discard so 19 we grab.
            $res->err("Unrecognized line: $_") if !/^([a-fA-F0-9]{19})[a-fA-F0-9]{16}:[0-9]+$/;
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

    $task->data->{next} = $num >= 0xffff ? 0 : $num+1 if !defined $task->arg;
    $task->done('%d hashes, %.0f -> %.0f KiB', $count, $old/1024, length($data)/1024);
};

1;
