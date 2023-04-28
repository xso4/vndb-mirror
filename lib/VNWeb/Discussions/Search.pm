package VNWeb::Discussions::Search;

use VNWeb::Prelude;
use VNWeb::Discussions::Lib;

my @BOARDS = (keys %BOARD_TYPE, 'w');

sub filters_ {
    state $schema = tuwf->compile({ type => 'hash', keys => {
        bq => { required => 0, default => '' },
        uq => { required => 0, default => '' },
        b  => { type => 'array', scalar => 1, onerror => \@BOARDS, values => { enum => \@BOARDS } },
        t  => { anybool => 1 },
        p  => { page => 1 },
    }});
    my $filt = tuwf->validate(get => $schema)->data;
    my %boards = map +($_,1), $filt->{b}->@*;

    my $u = $filt->{uq} && tuwf->dbVali('SELECT id FROM users WHERE', $filt->{uq} =~ /^u$RE{num}$/ ? 'id = ' : 'lower(username) =', \lc $filt->{uq});

    form_ method => 'get', action => tuwf->reqPath(), sub {
        boardtypes_;
        table_ class => 'boardsearchoptions', sub { tr_ sub {
                td_ sub {
                    select_ multiple => 1, size => scalar @BOARDS, name => 'b', sub {
                        option_ $boards{$_} ? (selected => 1) : (), value => $_, $_ eq 'w' ? 'Reviews' : $BOARD_TYPE{$_}{txt} for @BOARDS;
                    }
                };
                td_ sub {
                    input_ type => 'text', class => 'text', name => 'bq', style => 'width: 400px', placeholder => 'Search', value => $filt->{bq};
                    br_;
                    input_ type => 'text', class => 'text', name => 'uq', style => 'width: 150px', placeholder => 'Username or id', value => $filt->{uq};
                    b_ 'User not found.' if $filt->{uq} && !$u;

                    p_ class => 'linkradio', sub {
                        input_ type => 'checkbox', name => 't', id => 't', value => 1, $filt->{t} ? (checked => 'checked') : ();
                        label_ for => 't', 'Only search thread titles';
                    };

                    input_ type => 'submit', class => 'submit', value => 'Search';
                    debug_ $filt;
                };
            };
        }
    };
    ($filt, $u)
}


sub noresults_ {
    article_ sub {
        h1_ 'No results';
        p_ 'No threads or messages found matching your criteria.';
    };
}


sub posts_ {
    my($filt, $u) = @_;

    # Use websearch_to_tsquery() to convert the query string into a tsquery.
    # Also match against an empty string to see if the query doesn't consist of only negative matches.
    my $ts = tuwf->dbVali('
        WITH q(q) AS (SELECT websearch_to_tsquery(', \$filt->{bq}, '))
        SELECT CASE WHEN numnode(q) = 0 OR q @@ \'\' THEN NULL ELSE q END FROM q');
    return noresults_ if !$ts;

    my $reviews = grep $_ eq 'w', $filt->{b}->@*;
    my @tboards = grep $_ ne 'w', $filt->{b}->@*;
    return noresults_ if !$reviews && !@tboards;

    # HACK: The bbcodes are stripped from the original messages when creating
    # the headline, so they are guaranteed not to show up in the message. This
    # means we can re-use them for highlighting without worrying that they
    # conflict with the message contents.

    my($posts, $np) = tuwf->dbPagei({ results => 20, page => $filt->{p} }, q{
        SELECT m.id, m.num, m.title
             , }, sql_user(), q{
             , }, sql_totime('m.date'), q{as date
             , ts_headline('english', strip_bb_tags(strip_spoilers(m.msg)),}, \$ts, ',',
                 \'MaxFragments=2,MinWords=15,MaxWords=40,StartSel=[raw],StopSel=[/raw],FragmentDelimiter=[code]',
               ') as headline
          FROM (', sql_join('UNION',
             @tboards ?
                sql('SELECT tp.tid, tp.num, t.title, tp.uid, tp.date, tp.msg
                       FROM threads_posts tp
                       JOIN threads t ON t.id = tp.tid
                      WHERE NOT t.hidden AND NOT t.private AND tp.hidden IS NULL
                        AND bb_tsvector(tp.msg) @@', \$ts,
                            $u ? ('AND tp.uid =', \$u) : (),
                            @tboards < keys %BOARD_TYPE ? ('AND t.id IN(SELECT tid FROM threads_boards WHERE type IN', \@tboards, ')') : ()
             ) : (), $reviews ? (
                 sql('SELECT w.id, 0, v.title[1+1], w.uid, w.date, w.text
                        FROM reviews w
                        JOIN', vnt, 'v ON v.id = w.vid
                       WHERE NOT w.c_flagged AND bb_tsvector(w.text) @@', \$ts,
                             $u ? ('AND w.uid =', \$u) : ()),
                 sql('SELECT wp.id, wp.num, v.title[1+1], wp.uid, wp.date, wp.msg
                        FROM reviews_posts wp
                        JOIN reviews w ON w.id = wp.id
                        JOIN', vnt, 'v ON v.id = w.vid
                       WHERE NOT w.c_flagged AND wp.hidden IS NULL AND bb_tsvector(wp.msg) @@', \$ts,
                             $u ? ('AND wp.uid =', \$u) : ()),
             ) : ()), ') m (id, num, title, uid, date, msg)
          LEFT JOIN users u ON u.id = m.uid
         ORDER BY m.date DESC'
    );

    return noresults_ if !@$posts;

    my sub url { '?'.query_encode %$filt, @_ }
    paginate_ \&url, $filt->{p}, $np, 't';
    article_ class => 'browse postsearch', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1_1', 'Id';
                td_ class => 'tc1_2', '';
                td_ class => 'tc2', 'Date';
                td_ class => 'tc3', 'User';
                td_ class => 'tc4', sub { txt_ 'Message'; debug_ $posts; };
            }};
            tr_ sub {
                my $l = $_;
                my $link = "/$l->{id}".($l->{num}?".$l->{num}":'');
                td_ class => 'tc1_1', sub { a_ href => $link, $l->{id} };
                td_ class => 'tc1_2', sub { a_ href => $link, '.'.$l->{num} if $l->{num} };
                td_ class => 'tc2', fmtdate $l->{date};
                td_ class => 'tc3', sub { user_ $l };
                td_ class => 'tc4', sub {
                    div_ class => 'title', sub { a_ href => $link, $l->{title} };
                    div_ class => 'thread', sub { lit_(
                        xml_escape($l->{headline})
                            =~ s/\[raw\]/<b>/gr
                            =~ s/\[\/raw\]/<\/b>/gr
                            =~ s/\[code\]/<small>...<\/small><br \/>/gr
                    )};
                };
            } for @$posts;
        }
    };
    paginate_ \&url, $filt->{p}, $np, 'b';
}


sub threads_ {
    my($filt, $u) = @_;

    my @boards = grep $_ ne 'w', $filt->{b}->@*; # Can't search reviews by title
    return noresults_ if !@boards;

    my $where = sql_and
        @boards < keys %BOARD_TYPE ? sql('t.id IN(SELECT tid FROM threads_boards WHERE type IN', \@boards, ')') : (),
        $u ? sql('EXISTS(SELECT 1 FROM threads_posts tp WHERE tp.tid = t.id AND tp.num = 1 AND tp.uid =', \$u, ')') : (),
        map sql('t.title ilike', \('%'.sql_like($_).'%')), grep length($_) > 0, split /[ ,._-]/, $filt->{bq};

    noresults_ if !threadlist_
        where    => $where,
        results  => 50,
        page     => $filt->{p},
        paginate => sub { '?'.query_encode %$filt, @_ };
}


TUWF::get qr{/t/search}, sub {
    framework_ title => 'Search the discussion board',
    sub {
        my($filt, $u);
        article_ sub {
            h1_ 'Search the discussion board';
            ($filt, $u) = filters_;
        };
        posts_   $filt, $u if $filt->{bq} && !$filt->{t};
        threads_ $filt, $u if $filt->{bq} &&  $filt->{t};
    };
};

1;
