package VNWeb::TT::Lib;

use VNWeb::Prelude;
use Exporter 'import';

our @EXPORT = qw/ tagscore_ enrich_group tree_ parents_ /;

sub tagscore_ {
    my($s, $ign) = @_;
    div_ mkclass(tagscore => 1, negative => $s < 0, ignored => $ign), sub {
        span_ sprintf '%.1f', $s;
        div_ style => sprintf('width: %.0fpx', abs $s/3*30), '';
    };
}


# Add a 'group' name for traits
sub enrich_group {
    my($type, @lst) = @_;
    enrich_merge id => 'SELECT t.id, g.name AS "group" FROM traits t JOIN traits g ON g.id = t."group" WHERE t.id IN', @lst if $type eq 'i';
}


sub tree_ {
    my($type, $id) = @_;
    my $table = $type eq 'g' ? 'tag' : 'trait';
    my $top = tuwf->dbAlli(
        "SELECT id, name, c_items FROM ${table}s
          WHERE state = 1+1
            AND", $id ? sql "id IN(SELECT $table FROM ${table}s_parents WHERE parent = ", \$id, ')'
                      : "NOT EXISTS(SELECT 1 FROM ${table}s_parents WHERE $table = id)", "
          ORDER BY ", $type eq 'g' || $id ? 'name' : '"order"'
    );
    return if !@$top;

    enrich childs => id => parent => sub { sql
        "SELECT tp.parent, t.id, t.name, t.c_items FROM ${table}s t JOIN ${table}s_parents tp ON tp.$table = t.id WHERE state = 1+1 AND tp.parent IN", $_, 'ORDER BY name'
    }, $top;
    $top = [ sort { $b->{childs}->@* <=> $a->{childs}->@* } @$top ] if $type eq 'g' || $id;

    my sub lnk_ {
        a_ href => "/$type$_[0]{id}", $_[0]{name};
        b_ class => 'grayedout', " ($_[0]{c_items})" if $_[0]{c_items};
    }
    div_ class => 'mainbox', sub {
        h1_ $id ? ($type eq 'g' ? 'Child tags' : 'Child traits') : $type eq 'g' ? 'Tag tree' : 'Trait tree';
        ul_ class => 'tagtree', sub {
            li_ sub {
                lnk_ $_;
                my $sub = $_->{childs};
                ul_ sub {
                    li_ sub {
                        txt_ '> ';
                        lnk_ $_;
                    } for grep $_, $sub->@[0 .. (@$sub > 6 ? 4 : 5)];
                    li_ sub {
                        my $num = @$sub-5;
                        txt_ '> ';
                        a_ href => "/$type$_->{id}", style => 'font-style: italic', sprintf '%d more %s%s', $num, $table, $num == 1 ? '' : 's';
                    } if @$sub > 6;
                } if @$sub;
            } for @$top;
        };
        clearfloat_;
        br_;
    };
}


# Breadcrumbs-style listing of parent tags/traits
sub parents_ {
    my($type, $t) = @_;

    my %t;
    my $name = $type eq 'g' ? 'tag' : 'trait';
    push $t{$_->{child}}->@*, $_ for tuwf->dbAlli('
        WITH RECURSIVE p(id,child,name) AS (
            SELECT ', \$t->{id}, "::int, 0, NULL::text
            UNION
            SELECT t.id, p.id, t.name FROM p JOIN ${name}s_parents tp ON tp.${name} = p.id JOIN ${name}s t ON t.id = tp.parent
        ) SELECT * FROM p WHERE child <> 0 ORDER BY name
    ")->@*;

    my sub rec {
        $t{$_[0]} ? map { my $e=$_; map [ @$_, $e ], __SUB__->($e->{id}) } $t{$_[0]}->@* : []
    }

    p_ sub {
        join_ \&br_, sub {
            a_ href => "/$type", $type eq 'g' ? 'Tags' : 'Traits';
            for (@$_) {
                txt_ ' > ';
                a_ href => "/$type$_->{id}", $_->{name};
            }
            txt_ ' > ';
            txt_ $t->{name};
        }, rec($t->{id});
    };
}


1;
