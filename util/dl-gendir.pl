#!/usr/bin/perl

use strict;
use warnings;
use autodie;
use POSIX 'strftime';

chdir 'dl/dump';

my @pub = (glob('vndb-db-*'), glob('vndb-dev-*'), glob('vndb-votes-*'), glob('vndb-tags-*'), glob('vndb-traits-*'));

open my $F, '>', 'index.html~';
print $F q{<!DOCTYPE html>
<html>
  <head>
    <title>VNDB Database Downloads</title>
    <style type="text/css">
      th { text-align: left }
      td, th { padding: 1px 5px }
      td:nth-child(3), th:nth-child(3) { text-align: right }
    </style>
  </head>
  <body>
    <h1>VNDB Database Downloads</h1>
    <p>Refer to the <a href="https://vndb.org/d14">Database Dumps</a> page on VNDB.org for more information about these files.</p>
    <h2>Latest versions</h2>
    <table>
     <thead>
      <thead><tr><th>Name</th><th>Destination</th></tr></thead>
      <tbody>
};

printf $F q{<tr><td><a href="%s">%s</a></td><td>%s</td></tr>},
    $_, $_, readlink
    for (grep -l, @pub);

print $F q{
     </tbody>
    </table>
    <h2>Files</h2>
    <table>
     <thead><tr><th>Name</th><th>Last modified</th><th>Size</th></tr></thead>
     <tbody>
};
printf $F q{<tr><td><a href="%s">%s</a></td><td>%s</td><td>%d</td></tr>},
    $_, $_, strftime('%F %T', gmtime((stat)[9])), -s
    for (grep !-l, @pub);

print $F q{</tbody></table></body>};
close $F;
rename 'index.html~', 'index.html';
