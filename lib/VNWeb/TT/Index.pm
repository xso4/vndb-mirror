package VNWeb::TT::Index;

use VNWeb::Prelude;
use VNWeb::TT::Lib 'enrich_group', 'tree_';


sub recent_ {
    my($type) = @_;
    my $lst = tuwf->dbAlli('SELECT id, name, ', sql_totime('added'), 'AS added FROM', $type eq 'g' ? 'tags' : 'traits', 'WHERE NOT hidden ORDER BY id DESC LIMIT 10');
    enrich_group $type, $lst;
    p_ class => 'mainopts', sub {
        a_ href => "/$type/list", 'Browse all '.($type eq 'g' ? 'tags' : 'traits');
    };
    h1_ 'Recently added';
    ul_ sub {
        li_ sub {
            txt_ fmtage $_->{added};
            txt_ ' ';
            small_ "$_->{group} / " if $_->{group};
            a_ href => "/$_->{id}", $_->{name};
        } for @$lst;
    };
}


sub popular_ {
    my($type) = @_;
    my $lst = tuwf->dbAlli('SELECT id, name, c_items FROM', $type eq 'g' ? 'tags' : 'traits', 'WHERE NOT hidden AND c_items > 0 AND applicable ORDER BY c_items DESC LIMIT 10');
    enrich_group $type, $lst;
    p_ class => 'mainopts', sub {
        a_ href => '/g/links', 'Recently tagged';
    } if $type eq 'g';
    h1_ 'Popular';
    ul_ sub {
        li_ sub {
            small_ "$_->{group} / " if $_->{group};
            a_ href => "/$_->{id}", $_->{name};
            txt_ " ($_->{c_items})";
        } for @$lst;
    };
}


sub moderation_ {
    my($type) = @_;
    my $lst = tuwf->dbAlli('SELECT id, name, ', sql_totime('added'), 'AS added FROM', $type eq 'g' ? 'tags' : 'traits', 'WHERE hidden AND NOT locked ORDER BY added DESC LIMIT 10');
    enrich_group $type, $lst;
    h1_ 'Awaiting moderation';
    ul_ sub {
        li_ 'The moderation queue is empty!' if !@$lst;
        li_ sub {
            txt_ fmtage $_->{added};
            txt_ ' ';
            small_ "$_->{group} / " if $_->{group};
            a_ href => "/$_->{id}", $_->{name};
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
        article_ sub {
            p_ class => 'mainopts', sub {
                a_ href => "/$type/new", 'Create a new '.($type eq 'g' ? 'tag' : 'trait') if can_edit $type => {};
            };
            h1_ $type eq 'g' ? 'Search tags' : 'Search traits';
            form_ action => "/$type/list", sub {
                searchbox_ $type => '';
            };
        };
        tree_ $type;
        div_ class => 'threelayout', sub {
            article_ sub { recent_ $type };
            article_ sub { popular_ $type };
            article_ sub { moderation_ $type };
        };
    };
};

1;
