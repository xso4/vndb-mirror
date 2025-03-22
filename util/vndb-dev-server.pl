#!/usr/bin/perl
use Cwd 'abs_path';
(my $ROOT = abs_path $0) =~ s{/util/vndb-dev-server\.pl$}{};
chdir $ROOT;
exec qw{util/vndb.pl --http=0.0.0.0:3000 --monitor --debug};
