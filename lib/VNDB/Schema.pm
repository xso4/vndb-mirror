# Utility functions to parse the files in sql/ and extract information and
# perform a few simple sanity checks.
#
# This is not a full-blown SQL parser. The code makes all kinds of assumptions
# about the formatting of the .sql files.

package VNDB::Schema;

use v5.12;
use warnings;

my $ROOT = $INC{'VNDB/Schema.pm'} =~ s{/lib/VNDB/Schema\.pm}{}r;


# Reads schema.sql and returns a hashref with the following structure:
# {
#   vn => {
#       name => 'vn',
#       dbentry_type => 'v',
#       cols => [
#           {
#               name => 'id',
#               type => 'serial',
#               decl => 'id SERIAL', # full declaration, exluding comments and PRIMARY KEY marker
#               pub => 1,
#           }, ...
#       ],
#       primary => ['id'],
#   }
# }
sub schema {
    my %schema;
    my $table;
    open my $F, '<', "$ROOT/sql/schema.sql" or die "schema.sql: $!";
    while(<$F>) {
        chomp;
        next if /^\s*--/ || /^\s*$/;
        next if /^\s*CREATE\s+(?:TYPE|SEQUENCE|FUNCTION|DOMAIN|VIEW)/;

        if(/^\s*CREATE\s+TABLE\s+([^ ]+)/) {
            die "Unexpected 'CREATE TABLE $1'\n" if $table;
            $table = $1;
            $schema{$table}{name} = $table;
            $schema{$table}{dbentry_type} = $1 if /--.*\s+dbentry_type=(.)/;
            $schema{$table}{cols} = [];

        } elsif(/^\s*\);/) {
            $table = undef;

        } elsif(/^\s+(?:CHECK|CONSTRAINT)/) {
            # ignore

        } elsif($table && /^\s+PRIMARY\s+KEY\s*\(([^\)]+)\)/i) {
            die "Double primary key for '$table'?\n" if $schema{$table}{primary};
            $schema{$table}{primary} = [ map s/\s*"?([^\s"]+)"?\s*/$1/r, split /,/, $1 ];

        } elsif($table && s/^\s+"?([^"\( ]+)"?\s+//) {
            my $col = { name => $1 };
            push @{$schema{$table}{cols}}, $col;

            $col->{pub} = /--.*\[pub\]/;
            s/,?\s*(?:--.*)?$//;

            if(s/\s+PRIMARY\s+KEY//i) {
                die "Double primary key for '$table'?\n" if $schema{$table}{primary};
                $schema{$table}{primary} = [ $col->{name} ];
            }
            $col->{decl} = "\"$col->{name}\" $_";
            $col->{type} = lc s/^([^ ]+)\s.+/$1/r;
        }
    }

    \%schema
}


# Parses types from schema.sql and returns a hashref with the following structure:
# {
#   anime_type => {
#       decl => 'CREATE TYPE ..;'
#   }, ..
# }
sub types {
    my %types;
    open my $F, '<', "$ROOT/sql/schema.sql" or die "schema.sql: $!";
    while(<$F>) {
        chomp;
        if(/^CREATE (?:TYPE|DOMAIN) ([^ ]+)/) {
            $types{$1} = { decl => $_ };
        }
    }
    \%types
}


# Parses foreign key references from tableattrs.sql and returns an arrayref:
# [
#   {
#       decl => 'ALTER TABLE ..;',
#       from_table => 'vn_anime',
#       from_cols => ['id'],
#       to_table => 'vn',
#       to_cols => ['id'],
#       name => 'vn_anime_id_fkey'
#   }, ..
# ]
sub references {
    my @ref;
    open my $F, '<', "$ROOT/sql/tableattrs.sql" or die "tableattrs.sql: $!";
    while(<$F>) {
        chomp;
        next if !/^\s*ALTER\s+TABLE\s+([^ ]+)\s+ADD\s+CONSTRAINT\s+([^ ]+)\s+FOREIGN\s+KEY\s+\(([^\)]+)\)\s*REFERENCES\s+([^ ]+)\s*\(([^\)]+)\)/;
        push @ref, {
            decl => $_,
            from_table => $1,
            name => $2,
            from_cols => [ map s/"//r, split /\s*,\s*/, $3 ],
            to_table => $4,
            to_cols => [ map s/"//r, split /\s*,\s*/, $5 ]
        };
    }
    \@ref
}

1;
