#!/usr/bin/perl

# This script checks and updates all queries in the saved_queries table.

use v5.24;
use warnings;
use Cwd 'abs_path';
use TUWF;

my $ROOT;
BEGIN { ($ROOT = abs_path $0) =~ s{/util/saved-queries\.pl$}{}; }

use lib $ROOT.'/lib';
use VNDB::Config;

TUWF::set %{ config->{tuwf} };

require VNWeb::AdvSearch;


my($total, $updated, $err) = (0,0,0);

for my $r (tuwf->dbAlli('SELECT uid, qtype, name, query FROM saved_queries')->@*) {
    $total++;
    my $q = eval { tuwf->compile({advsearch => $r->{qtype}})->validate($r->{query})->data };
    if(!$q) {
        $err++;
        warn "Invalid query: u$r->{uid}, $r->{qtype}, \"$r->{name}\": $r->{query}\n";
        next;
    }
    my $qs = $q->query_encode;
    if(!$qs) {
        warn "Empty query: u$r->{uid}, $r->{qtype}, \"$r->{name}\": $r->{query}\n";
        next;
    }
    if($qs ne $r->{query}) {
        $updated++;
        tuwf->dbExeci('UPDATE saved_queries SET query =', \$qs, 'WHERE', { uid => $r->{uid}, qtype => $r->{qtype}, name => $r->{name} });
    }
}

tuwf->dbCommit;

printf "Updated %d/%d saved queries, %d errors.\n", $updated, $total, $err;
