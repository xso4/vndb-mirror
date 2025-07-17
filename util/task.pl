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

require $_ =~ s{^\Q$ROOT\E/lib/}{}r for (glob("$ROOT/lib/VNTask/*.pm"));

# TODO: multiprocess supervisor? regular auto-restarts might be nice too.

VNTask::Core::loop if !@ARGV;
VNTask::Core::one(@ARGV);
