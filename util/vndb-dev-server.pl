#!/usr/bin/perl
exec $0 =~ s/vndb-dev-server\.pl$/vndb.pl/r, qw{--http=0.0.0.0:3000 --monitor --debug}
