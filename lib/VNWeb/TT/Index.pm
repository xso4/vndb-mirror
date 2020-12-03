package VNWeb::TT::Index;

use VNWeb::Prelude;
use VNWeb::TT::Lib 'enrich_group';


sub tree_ {
    my($type) = @_;
    my $table = $type eq 'g' ? 'tag' : 'trait';
    my $top = tuwf->dbAlli(
        "SELECT id, name, c_items FROM ${table}s WHERE state = 1+1 AND NOT EXISTS(SELECT 1 FROM ${table}s_parents WHERE $table = id)
          ORDER BY ", $type eq 'g' ? 'name' : '"order"'
    );

    enrich childs => id => parent => sub { sql
        "SELECT tp.parent, t.id, t.name, t.c_items FROM ${table}s t JOIN ${table}s_parents tp ON tp.$table = t.id WHERE state = 1+1 AND tp.parent IN", $_, 'ORDER BY name'
    }, $top;
    $top = [ sort { $b->{childs}->@* <=> $a->{childs}->@* } @$top ] if $type eq 'g';

    my sub lnk_ {
        a_ href => "/$type$_[0]{id}", $_[0]{name};
        b_ class => 'grayedout', " ($_[0]{c_items})" if $_[0]{c_items};
    }
    div_ class => 'mainbox', sub {
        h1_ $type eq 'g' ? 'Tag tree' : 'Trait tree';
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


sub recent_ {
    my($type) = @_;
    my $lst = tuwf->dbAlli('SELECT id, name, ', sql_totime('added'), 'AS added FROM', $type eq 'g' ? 'tags' : 'traits', 'WHERE state = 1+1 ORDER BY added DESC LIMIT 10');
    enrich_group $type, $lst;
    p_ class => 'mainopts', sub {
        a_ href => "/$type/list", 'Browse all '.($type eq 'g' ? 'tags' : 'traits');
    };
    h1_ 'Recently added';
    ul_ sub {
        li_ sub {
            txt_ fmtage $_->{added};
            txt_ ' ';
            b_ class => 'grayedout', "$_->{group} / " if $_->{group};
            a_ href => "/$type$_->{id}", $_->{name};
        } for @$lst;
    };
}


sub popular_ {
    my($type) = @_;
    my $lst = tuwf->dbAlli('SELECT id, name, c_items FROM', $type eq 'g' ? 'tags' : 'traits', 'WHERE state = 1+1 AND c_items > 0 AND applicable ORDER BY c_items DESC LIMIT 10');
    enrich_group $type, $lst;
    p_ class => 'mainopts', sub {
        a_ href => '/g/links', 'Recently tagged';
    } if $type eq 'g';
    h1_ 'Popular';
    ul_ sub {
        li_ sub {
            b_ class => 'grayedout', "$_->{group} / " if $_->{group};
            a_ href => "/$type$_->{id}", $_->{name};
            txt_ " ($_->{c_items})";
        } for @$lst;
    };
}


sub moderation_ {
    my($type) = @_;
    my $lst = tuwf->dbAlli('SELECT id, name, ', sql_totime('added'), 'AS added FROM', $type eq 'g' ? 'tags' : 'traits', 'WHERE state = 0 ORDER BY added DESC LIMIT 10');
    enrich_group $type, $lst;
    h1_ 'Awaiting moderation';
    ul_ sub {
        li_ 'The moderation queue is empty!' if !@$lst;
        li_ sub {
            txt_ fmtage $_->{added};
            txt_ ' ';
            b_ class => 'grayedout', "$_->{group} / " if $_->{group};
            a_ href => "/$type$_->{id}", $_->{name};
        } for @$lst;
        li_ sub {
            br_;
            a_ href => "/$type/list?t=0;o=d;s=added", 'Moderation queue';
            txt_ ' - ';
            a_ href => "/$type/list?t=1;o=d;s=added", $type eq 'g' ? 'Denied tags' : 'Denied traits';
        };
    };
}


TUWF::get qr{/(?<type>[gi])}, sub {
    my $type = tuwf->capture('type');
    framework_ title => $type eq 'g' ? 'Tag index' : 'Trait index', index => 1, sub {
        div_ class => 'mainbox', sub {
            p_ class => 'mainopts', sub {
                a_ href => "/$type/new", 'Create a new'.($type eq 'g' ? 'tag' : 'trait') if can_edit $type => {};
            };
            h1_ $type eq 'g' ? 'Search tags' : 'Search traits';
            form_ action => "/$type/list", sub {
                searchbox_ $type => '';
            };
        };
        tree_ $type;
        div_ class => 'threelayout', sub {
            div_ sub { recent_ $type };
            div_ sub { popular_ $type };
            div_ sub { moderation_ $type };
        };
    };
};

1;
