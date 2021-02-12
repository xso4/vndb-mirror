package VNWeb::Discussions::Lib;

use VNWeb::Prelude;
use Exporter 'import';

our @EXPORT = qw/$BOARD_RE sql_visible_threads sql_boards enrich_boards threadlist_ boardsearch_ boardtypes_/;


our $BOARD_RE = join '|', map $_.($BOARD_TYPE{$_}{dbitem}?'(?:[1-9][0-9]{0,5})?':''), keys %BOARD_TYPE;


# Returns a WHERE condition to filter threads that the current user is allowed to see.
sub sql_visible_threads {
    return '1=1' if auth && auth->uid eq 'u2'; # Yorhel sees everything
    sql_and
        auth->permBoardmod ? () : ('NOT t.hidden'),
        sql('NOT t.private OR EXISTS(SELECT 1 FROM threads_boards WHERE tid = t.id AND type = \'u\' AND iid =', \auth->uid, ')');
}


# Returns a SELECT subquery with all board IDs
sub sql_boards {
    sql q{(   SELECT 'v'::board_type AS btype, id AS iid, title,    original FROM vn
    UNION ALL SELECT 'p'::board_type AS btype, id AS iid, name,     original FROM producers
    UNION ALL SELECT 'u'::board_type AS btype, id AS iid, username, NULL     FROM users
    )}
}


# Adds a 'boards' array to threads.
sub enrich_boards {
    my($filt, @lst) = @_;
    enrich boards => id => tid => sub { sql q{
        SELECT tb.tid, tb.type AS btype, tb.iid, b.title, b.original
          FROM threads_boards tb
          LEFT JOIN }, sql_boards(), q{b ON b.btype = tb.type AND b.iid = tb.iid
         WHERE }, sql_and(sql('tb.tid IN', $_[0]), $filt||()), q{
         ORDER BY tb.type, tb.iid
    }}, @lst;
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
sub threadlist_ {
    my %opt = @_;

    my $where = sql_and sql_visible_threads(), $opt{where}||();

    my $count = $opt{paginate} && tuwf->dbVali('SELECT count(*) FROM threads t WHERE', $where);
    return 0 if $opt{paginate} && !$count;

    my $lst = tuwf->dbPagei(\%opt, q{
        SELECT t.id, t.title, t.c_count, t.c_lastnum, t.locked, t.private, t.hidden, t.poll_question IS NOT NULL AS haspoll
             , }, sql_user('tfu', 'firstpost_'), ',', sql_totime('tf.date'), q{ as firstpost_date
             , }, sql_user('tlu', 'lastpost_'),  ',', sql_totime('tl.date'), q{ as lastpost_date
          FROM threads t
          JOIN threads_posts tf ON tf.tid = t.id AND tf.num = 1
          JOIN threads_posts tl ON tl.tid = t.id AND tl.num = t.c_lastnum
          LEFT JOIN users tfu ON tfu.id = tf.uid
          LEFT JOIN users tlu ON tlu.id = tl.uid
         WHERE }, $where, q{
         ORDER BY}, $opt{sort}||'tl.date DESC'
    );
    return 0 if !@$lst;

    enrich_boards $opt{boards}, $lst;

    paginate_ $opt{paginate}, $opt{page}, [ $count, $opt{results} ], 't' if $opt{paginate};
    div_ class => 'mainbox browse discussions', sub {
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
                    a_ mkclass(locked => $l->{locked}), href => "/$l->{id}", sub {
                        span_ class => 'pollflag', '[poll]' if $l->{haspoll};
                        span_ class => 'pollflag', '[private]' if $l->{private};
                        span_ class => 'pollflag', '[hidden]' if $l->{hidden};
                        txt_ shorten $l->{title}, 50;
                    };
                    b_ class => 'boards', sub {
                        join_ ', ', sub {
                            a_ href => '/t/'.($_->{iid}||$_->{btype}),
                                title => $_->{original}||$BOARD_TYPE{$_->{btype}}{txt},
                                shorten $_->{title}||$BOARD_TYPE{$_->{btype}}{txt}, 30;
                        }, $l->{boards}->@[0 .. min 4, $#{$l->{boards}}];
                        txt_ ', ...' if $l->{boards}->@* > 4;
                    };
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
        a_ href => $_->[0] eq 'index' ? '/t' : '/t/'.$_->[0], mkclass(optselected => $type && $type eq $_->[0]), $_->[1] for (
            [ index => 'Index'      ],
            [ all   => 'All boards' ],
            map [ $_, $BOARD_TYPE{$_}{txt} ], keys %BOARD_TYPE
        );
    };
}


1;
