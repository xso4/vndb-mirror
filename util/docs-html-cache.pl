#!/usr/bin/perl

use v5.36;
use FU::Pg;
use lib 'lib';
use VNDB::Func 'md2html';

my $db = FU::Pg->connect('dbname=vndb user=vndb');
my $txn = $db->txn;
$txn->q('UPDATE docs_hist SET html = $1 WHERE chid = $2', md2html($_->[1]), $_->[0])->exec for $txn->q('SELECT chid, content FROM docs_hist')->alla->@*;
$txn->q('UPDATE docs      SET html = $1 WHERE id   = $2', md2html($_->[1]), $_->[0])->exec for $txn->q('SELECT id,   content FROM docs'     )->alla->@*;
$txn->commit;
