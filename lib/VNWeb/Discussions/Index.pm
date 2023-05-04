package VNWeb::Discussions::Index;

use VNWeb::Prelude;
use VNWeb::Discussions::Lib;


TUWF::get qr{/t}, sub {
    framework_ title => 'Discussion board index', sub {
        form_ method => 'get', action => '/t/search', sub {
            article_ sub {
                h1_ 'Discussion board index';
                boardtypes_ 'index';
                boardsearch_;
                p_ class => 'center', sub {
                    a_ href => '/t/ge/new', 'Start a new thread';
                } if can_edit t => {};
            }
        };

        for my $b (keys %BOARD_TYPE) {
            nav_ sub {
                h1_ sub {
                    a_ href => "/t/$b", $BOARD_TYPE{$b}{txt};
                };
            };
            threadlist_
                where   => sql('t.id IN(SELECT tid FROM threads_boards WHERE type =', \$b, ')'),
                boards  => sql('NOT (tb.type =', \$b, 'AND tb.iid IS NULL)'),
                results => $BOARD_TYPE{$b}{index_rows},
                page    => 1;
        }
    }
};

1;
