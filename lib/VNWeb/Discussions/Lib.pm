package VNWeb::Discussions::Lib;

use VNWeb::Prelude;
use Exporter 'import';

our @EXPORT = qw/$BOARD_RE VISIBLE_THREADS enrich_boards threadlist_ boardsearch_ boardtypes_ notify_mentions/;


our $BOARD_RE = join '|', map $_.($BOARD_TYPE{$_}{dbitem}?'(?:[1-9][0-9]{0,5})?':''), keys %BOARD_TYPE;


# Returns a WHERE condition to filter threads that the current user is allowed to see.
sub VISIBLE_THREADS {
    return RAW 'true' if auth && auth->uid eq 'u2'; # Yorhel sees everything
    AND auth->permBoardmod ? () : ('NOT t.hidden'),
        SQL("NOT t.private OR EXISTS(SELECT 1 FROM threads_boards WHERE tid = t.id AND type = 'u' AND iid =", auth->uid, ')');
}


# Adds a 'boards' array to threads.
sub enrich_boards($filt, $lst) {
    fu->enrich(aoh => boards => sub { SQL '
        SELECT tb.tid, COALESCE(tb.iid::text, tb.type::text) AS id, tb.type AS btype, tb.iid, x.title
          FROM threads_boards tb, ', ITEM_INFO('tb.iid', 'NULL'), 'x
         WHERE ', AND(SQL('tb.tid', IN $_), $filt||()), '
         ORDER BY tb.type, tb.iid
    '}, $lst);
}


# Generate a thread list table, options:
#   where    => SQL for the WHERE clause ('t' is available as alias for 'threads').
#   boards   => SQL for the WHERE clause of the boards ('tb' as alias for 'threads_boards').
#   results  => Number of threads to display.
#   page     => Current page number.
#   paginate => sub {} reference that generates a url for paginate_(); pagination is disabled when not set.
#   sort     => SQL (default: tl.date DESC)
#
# Returns 1 if something was displayed, 0 if no threads matched the where clause.
sub threadlist_(%opt) {
    my $where = AND VISIBLE_THREADS, $opt{where}||();

    my $count = $opt{paginate} && fu->SQL('SELECT count(*) FROM threads t WHERE', $where)->val;
    return 0 if $opt{paginate} && !$count;

    my $lst = fu->SQL('
        SELECT t.id, t.title, t.c_count, t.c_lastnum, t.locked, t.private, t.hidden, t.poll_question IS NOT NULL AS haspoll
             , ', USER('tfu', 'firstpost_'), ', tf.date as firstpost_date
             , ', USER('tlu', 'lastpost_'),  ', tl.date as lastpost_date
          FROM threads t
          JOIN threads_posts tf ON tf.tid = t.id AND tf.num = 1
          JOIN threads_posts tl ON tl.tid = t.id AND tl.num = t.c_lastnum
          LEFT JOIN users tfu ON tfu.id = tf.uid
          LEFT JOIN users tlu ON tlu.id = tl.uid
         WHERE ', $where, '
         ORDER BY', RAW($opt{sort}||'tl.date DESC'), '
         LIMIT', $opt{results}, OFFSET => $opt{results}*($opt{page}-1)
    )->allh;
    return 0 if !@$lst;

    enrich_boards $opt{boards}, $lst;

    paginate_ $opt{paginate}, $opt{page}, [ $count, $opt{results} ], 't' if $opt{paginate};
    article_ class => 'browse discussions', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub { txt_ 'Topic'; debug_ $lst };
                td_ class => 'tc2', 'Replies';
                td_ class => 'tc3', 'Starter';
                td_ class => 'tc4', 'Last post';
            }};
            tr_ sub {
                my $l = $_;
                td_ class => 'tc1', sub {
                    my $system = $l->{private} && $l->{firstpost_id} && $l->{firstpost_id} eq 'u1';
                    a_ class => !$system && $l->{locked} ? 'locked' : undef, href => "/$l->{id}", sub {
                        span_ class => 'pollflag', '[poll]' if $l->{haspoll};
                        span_ class => 'pollflag', $system ? '[system]' : '[private]' if $l->{private};
                        span_ class => 'pollflag', '[hidden]' if $l->{hidden};
                        txt_ shorten $l->{title}, 50;
                    };
                    span_ class => 'boards', sub {
                        join_ ', ', sub {
                            a_ href => '/t/'.($_->{iid}||$_->{btype}),
                                $_->{title} ? tlang(@{$_->{title}}[0,1]) : (),
                                title => $_->{title} ? $_->{title}[3] : $BOARD_TYPE{$_->{btype}}{txt},
                                shorten $_->{title} ? $_->{title}[1] : $BOARD_TYPE{$_->{btype}}{txt}, 30;
                        }, $l->{boards}->@[0 .. min 4, $#{$l->{boards}}];
                        txt_ ', ...' if $l->{boards}->@* > 4;
                    } if !$system;
                };
                td_ class => 'tc2', $l->{c_count}-1;
                td_ class => 'tc3', sub { user_ $l, 'firstpost_' };
                td_ class => 'tc4', sub {
                    user_ $l, 'lastpost_';
                    txt_ ' @ ';
                    a_ href => "/$l->{id}.$l->{c_lastnum}#last", fmtdate $l->{lastpost_date}, 'full';
                };
            } for @$lst;
        }
    };
    paginate_ $opt{paginate}, $opt{page}, [ $count, $opt{results} ], 'b' if $opt{paginate};
    1;
}


sub boardsearch_ {
    my($type) = @_;
    form_ action => '/t/search', sub {
        fieldset_ class => 'search', sub {
            input_ type => 'text', name => 'bq', id => 'bq', class => 'text';
            input_ type => 'hidden', name => 'b', value => $type if $type && $type ne 'all';
            input_ type => 'submit', class => 'submit', value => 'Search!';
        }
    }
}


sub boardtypes_ {
    my($type) = @_;
    p_ class => 'browseopts', sub {
        a_ href => $_->[0] eq 'index' ? '/t' : '/t/'.$_->[0], class => $type && $type eq $_->[0] ? 'optselected' : undef, $_->[1] for (
            [ index => 'Index'      ],
            [ all   => 'All boards' ],
            map [ $_, $BOARD_TYPE{$_}{txt} ], keys %BOARD_TYPE
        );
    };
}


# Should be called after a new comment has been added.
# Should NOT be called for private/hidden threads.
sub notify_mentions($id, $num, $msg) {
    my(%uids, %posts);
    VNDB::BBCode::parse($msg, sub($raw, $token, @) {
        $uids{$raw} = 1 if $token eq 'dblink' && $raw =~ /^$RE{uid}$/;
        $posts{$raw} = 1 if $token eq 'dblink' && $raw =~ /^[tw]$RE{num}\.$RE{num}$/;
        1;
    });

    my sub noti($type, $uid) {
        fu->SQL("UPDATE notifications SET ntype = ntype ||", [$type], WHERE { uid => $uid, iid => $id, num => $num })->exec ||
        fu->SQL('INSERT INTO notifications', VALUES { uid => $uid, iid => $id, num => $num, ntype => [$type]})->exec;
    }

    noti ment => $_ for keys %uids ? fu->SQL('SELECT id FROM users WHERE id', IN [keys %uids])->flat->@* : ();

    my %postuids;
    for (keys %posts) {
        my $uid = fu->sql(
            'SELECT uid FROM threads_posts WHERE tid = $1 AND num = $2 UNION SELECT uid FROM reviews_posts WHERE id = $1 AND num = $2',
            /([tw]$RE{num})\.($RE{num})/
        )->val;
        $postuids{$uid} = 1 if $uid;
    }
    noti postment => $_ for keys %postuids;
}


1;
