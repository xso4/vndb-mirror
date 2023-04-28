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
    enrich_merge id => 'SELECT t.id, g.name AS "group" FROM traits t JOIN traits g ON g.id = t.gid WHERE t.id IN', @lst if $type eq 'i';
}


sub tree_ {
    my($type, $id) = @_;
    my $table = $type eq 'g' ? 'tags' : 'traits';
    my $top = tuwf->dbAlli(
        "SELECT id, name, c_items FROM $table t
          WHERE NOT hidden
            AND", $id ? sql "id IN(SELECT id FROM ${table}_parents WHERE parent = ", \$id, ')'
                      : "NOT EXISTS(SELECT 1 FROM ${table}_parents tp WHERE tp.id = t.id)", "
          ORDER BY ", $type eq 'g' || $id ? 'name' : 'gorder'
    );
    return if !@$top;

    enrich childs => id => parent => sub { sql
        "SELECT tp.parent, t.id, t.name, t.c_items FROM $table t JOIN ${table}_parents tp ON tp.id = t.id WHERE NOT hidden AND tp.parent IN", $_, 'ORDER BY name'
    }, $top;
    $top = [ sort { $b->{childs}->@* <=> $a->{childs}->@* } @$top ] if $type eq 'g' || $id;

    my sub lnk_ {
        a_ href => "/$_[0]{id}", $_[0]{name};
        small_ " ($_[0]{c_items})" if $_[0]{c_items};
    }
    article_ sub {
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
                        a_ href => "/$_->{id}", style => 'font-style: italic', sprintf '%d more %s%s', $num, $type eq 'g' ? 'tag' : 'trait', $num == 1 ? '' : 's';
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
    my $table = $type eq 'g' ? 'tags' : 'traits';
    push $t{$_->{child}}->@*, $_ for tuwf->dbAlli("
        WITH RECURSIVE p(id,child,name,main) AS (
            SELECT t.id, tp.id, t.name, tp.main FROM ${table}_parents tp JOIN $table t ON t.id = tp.parent WHERE tp.id =", \$t->{id}, "
            UNION
            SELECT t.id, p.id, t.name, tp.main FROM p JOIN ${table}_parents tp ON tp.id = p.id JOIN $table t ON t.id = tp.parent
        ) SELECT * FROM p ORDER BY main DESC, name
    ")->@*;

    my sub rec {
        $t{$_[0]} ? map { my $e=$_; map [ @$_, $e ], __SUB__->($e->{id}) } $t{$_[0]}->@* : []
    }

    p_ sub {
        join_ \&br_, sub {
            a_ href => "/$type", $type eq 'g' ? 'Tags' : 'Traits';
            for (@$_) {
                txt_ ' > ';
                a_ href => "/$_->{id}", $_->{name};
            }
            txt_ ' > ';
            txt_ $t->{name};
        }, rec($t->{id});
    };
}


1;
