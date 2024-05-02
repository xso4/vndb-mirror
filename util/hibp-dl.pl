#!/usr/bin/perl

# This script downloads a full copy of the Have I Been Pwned SHA1 database
# using their range API.
# -> https://haveibeenpwned.com/API/v3#PwnedPasswords
#
# Output database format:
#   var/hibp/####  -> file for hashes prefixed with those two bytes
#
#   Each file is an ordered concatenation of raw hashes, excluding the first
#   two bytes (part of the filename) and the last 8 bytes (truncated hashes),
#   so each hash is represented with 10 bytes.
#
#   This means we actually store 96bit truncated SHA1 hashes, which should
#   still provide a very low probability of collision. A bloom filter may have
#   a lower collision probability for the same amount of space, but is also
#   more complex and expensive to manage.

use v5.28;
use warnings;
use AE;
use AnyEvent::HTTP;

my $API = 'https://api.pwnedpasswords.com/range/';
my $concurrency = 5;
my $lastnum = 0;
my $run = AE::cv;

$ENV{VNDB_VAR} //= 'var';

mkdir "$ENV{VNDB_VAR}/hibp";
chdir "$ENV{VNDB_VAR}/hibp" or die $!;


$AnyEvent::HTTP::MAX_PER_HOST = $concurrency;

sub save {
    my($file, $count, $data) = @_;
    {
        open my $OUT, '>', "$file~" or die $!;
        print $OUT $data;
    }
    rename "$file~", $file or die $!;
    say sprintf '%s -> %d hashes, %.0f KiB', $file, $count, length($data)/1024;
}

sub fetch_one {
    my($file, $count, $data, $midnum) = @_;

    my $mid = sprintf '%X', $midnum;
    http_request GET => $API.$file.$mid, persistent => 1, sub {
        my($body, $hdr) = @_;
        if($hdr->{Status} =~ /^2/) {
            for (split /\r?\n/, $body) {
                # 40-5 -> 35 hex chars per hash; 16 of which we discard so 19 we grab.
                warn "$file.$mid Unrecognized line: $_\n" if !/^([a-fA-F0-9]{19})[a-fA-F0-9]{16}:[0-9]+$/;
                $count++;
                $data .= pack 'H*', $mid.$1;
            }
            if($midnum == 15) {
                save $file, $count, $data;
                fetch_next();
            } else {
                fetch_one($file, $count, $data, $midnum+1);
            }
        } else {
            warn "$file.$mid: $hdr->{Status}\n";
            fetch_next();
        }
    };
}

sub fetch_next {
    my $file;
    do {
        my $filenum = $lastnum++;
        return $run->end if $filenum > 65535;
        $file = sprintf '%04X', $filenum;
    } while(-s $file);

    fetch_one $file, 0, '', 0;
}

$run->begin for (1..$concurrency);
fetch_next() for (1..$concurrency);
$run->recv;
