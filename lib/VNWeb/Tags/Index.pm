package VNWeb::Tags::Index;

use VNWeb::Prelude;


sub tree_ {
    my $top = tuwf->dbAlli('SELECT id, name, c_items FROM tags WHERE state = 1+1 AND NOT EXISTS(SELECT 1 FROM tags_parents WHERE tag = id) ORDER BY name');

    enrich childs => id => parent => sub { sql
        'SELECT tp.parent, t.id, t.name, t.c_items FROM tags t JOIN tags_parents tp ON tp.tag = t.id WHERE state = 1+1 AND tp.parent IN', $_, 'ORDER BY name'
    }, $top;
    $top = [ sort { $b->{childs}->@* <=> $a->{childs}->@* } @$top ];

    my sub lnk_ {
        a_ href => "/g$_[0]{id}", $_[0]{name};
        b_ class => 'grayedout', " ($_[0]{c_items})" if $_[0]{c_items};
    }
    div_ class => 'mainbox', sub {
        h1_ 'Tag tree';
        ul_ class => 'tagtree', sub {
            li_ sub {
                lnk_ $_;
                my $sub = $_->{childs};
                ul_ sub {
                    li_ sub {
                        txt_ '> ';
                        lnk_ $_;
                    } for grep $_, $sub->@[0..4];
                    li_ sub {
                        my $num = @$sub-5;
                        txt_ '> ';
                        a_ href => "/g$_->{id}", style => 'font-style: italic', sprintf '%d more tag%s', $num, $num == 1 ? '' : 's';
                    } if @$sub > 6;
                } if @$sub;
            } for @$top;
        };
        clearfloat_;
        br_;
    };
}


sub recent_ {
    my $lst = tuwf->dbAlli('SELECT id, name, ', sql_totime('added'), 'AS added FROM tags WHERE state = 1+1 ORDER BY added DESC LIMIT 10');
    p_ class => 'mainopts', sub {
        a_ href => '/g/list', 'Browse all tags';
    };
    h1_ 'Recently added';
    ul_ sub {
        li_ sub {
            txt_ fmtage $_->{added};
            txt_ ' ';
            a_ href => "/g$_->{id}", $_->{name};
        } for @$lst;
    };
}


sub popular_ {
    my $lst = tuwf->dbAlli('SELECT id, name, c_items FROM tags WHERE state = 1+1 AND c_items > 0 AND applicable ORDER BY c_items DESC LIMIT 10');
    p_ class => 'mainopts', sub {
        a_ href => '/g/links', 'Recently tagged';
    };
    h1_ 'Popular';
    ul_ sub {
        li_ sub {
            a_ href => "/g$_->{id}", $_->{name};
            txt_ " ($_->{c_items})";
        } for @$lst;
    };
}


sub moderation_ {
    my $lst = tuwf->dbAlli('SELECT id, name, ', sql_totime('added'), 'AS added FROM tags WHERE state = 0 ORDER BY added DESC LIMIT 10');
    h1_ 'Awaiting moderation';
    ul_ sub {
        li_ 'The moderation queue is empty!' if !@$lst;
        li_ sub {
            txt_ fmtage $_->{added};
            txt_ ' ';
            a_ href => "/g$_->{id}", $_->{name};
        } for @$lst;
        li_ sub {
            br_;
            a_ href => '/g/list?t=0;o=d;s=added', 'Moderation queue';
            txt_ ' - ';
            a_ href => '/g/list?t=1;o=d;s=added', 'Denied tags';
        };
    };
}


TUWF::get qr{/g}, sub {
    framework_ title => 'Tag index', index => 1, sub {
        div_ class => 'mainbox', sub {
            p_ class => 'mainopts', sub {
                a_ href => '/g/new', 'Create a new tag' if can_edit g => {};
            };
            h1_ 'Search tags';
            form_ action => '/g/list', sub {
                searchbox_ g => '';
            };
        };
        tree_;
        table_ class => 'mainbox threelayout', sub {
            tr_ sub {
                td_ \&recent_;
                td_ \&popular_;
                td_ \&moderation_;
            };
        };

    };
};

1;
