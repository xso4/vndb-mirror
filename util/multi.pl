#!/usr/bin/env perl

use strict;
use warnings;
use Cwd 'abs_path';

my $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/multi\.pl$}{} }

use lib $ROOT.'/lib';
use Multi::Core;

my $quiet = grep '-q', @ARGV;

Multi::Core::run $quiet;
