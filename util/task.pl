#!/usr/bin/env perl

use v5.36;

use Cwd 'abs_path';
our $ROOT;
BEGIN {
    $ROOT = abs_path($0) =~ s{/util/task\.pl$}{}r;
    $ENV{TZ} = 'UTC';
}
use lib $ROOT.'/lib';
use VNTask::Core ();

require $_ =~ s{^\Q$ROOT\E/lib/}{}r for (glob("$ROOT/lib/VNTask/*.pm"), glob("$ROOT/lib/VNTask/*/*.pm"));

# TODO: multiprocess supervisor? regular auto-restarts might be nice too.

if (!@ARGV) {
    VNTask::Core::loop
} elsif ($ARGV[0] eq 'el') {
    # Special CLI argument handling for:
    #
    #   el $id
    #   el $site $value
    #
    # To triage and fetch the given extlink.
    my $id = @ARGV == 2 ? $ARGV[1] : VNTask::Core::db->q('SELECT id FROM extlinks WHERE site = $1 AND value = $2', $ARGV[1], $ARGV[2])->val;
    die "No link found.\n" if !$id;
    VNTask::Core::one('el-triage', $id);
    my $queue = VNTask::Core::db->q('SELECT queue FROM extlinks WHERE id = $1', $id)->val;
    VNTask::Core::one($queue, $id) if $queue;

} else {
    VNTask::Core::one(@ARGV);
}
