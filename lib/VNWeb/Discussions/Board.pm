package VNWeb::Discussions::Board;

use VNWeb::Prelude;
use VNWeb::Discussions::Lib;


FU::get qr{/t/(all|$BOARD_RE)}, sub($id) {
    not_moe;
    my($type) = $id =~ /^([^0-9]+)/;
    $id = undef if $id !~ /[0-9]$/;

    my $page = fu->query(p => { upage => 1 });

    my $obj = $id ? dbobj $id : undef;
    fu->notfound if $id && !$obj->{id};
    fu->notfound if $id && $id =~ /^u/ && $obj->{entry_hidden} && !auth->isMod;

    my $title = $obj ? "Related discussions for $obj->{title}[1]" : $type eq 'all' ? 'All boards' : $BOARD_TYPE{$type}{txt};
    my $createurl = '/t/'.($id || ($type eq 'db' ? 'db' : 'ge')).'/new';

    framework_ title => $title, dbobj => $obj, tab => 'disc',
    sub {
        article_ sub {
            h1_ $title;
            boardtypes_ $type;
            boardsearch_ $type if !$id;
            p_ class => 'center', sub {
                a_ href => $createurl, 'Start a new thread';
            } if can_edit t => {};
        };

        threadlist_
            where    => $type ne 'all' && SQL('t.id IN(SELECT tid FROM threads_boards WHERE type =', $type, $id ? ('AND iid =', $id) : (), ')'),
            boards   => $type ne 'all' && SQL('NOT (tb.type =', $type, 'AND tb.iid IS NOT DISTINCT FROM', $id, ')'),
            results  => 50,
            sort     => $type eq 'an' ? 't.id DESC' : undef,
            page     => $page,
            paginate => sub { "?p=$_" }
        or article_ sub {
            h1_ 'An empty board';
            p_ class => 'center', sub {
                txt_ "Nobody's started a discussion on this board yet. Why not ";
                a_ href => $createurl, 'create a new thread';
                txt_ ' yourself?';
            }
        }
    };
};

1;
