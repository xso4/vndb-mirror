#!/usr/bin/perl

use v5.36;
use DBI;
use lib 'lib';
use VNDB::Func 'md2html';

my $db = DBI->connect('dbi:Pg:dbname=vndb', 'vndb', undef, { RaiseError => 1, AutoCommit => 0 });
$db->do('UPDATE docs_hist SET html = ? WHERE chid = ?', undef, md2html($_->[1]), $_->[0]) for $db->selectall_array('SELECT chid, content FROM docs_hist');
$db->do('UPDATE docs      SET html = ? WHERE id   = ?', undef, md2html($_->[1]), $_->[0]) for $db->selectall_array('SELECT id,   content FROM docs'     );
$db->commit;
