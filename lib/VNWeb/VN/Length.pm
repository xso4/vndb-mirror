package VNWeb::VN::Length;

use VNWeb::Prelude;

# Also used from VN::Page
sub can_vote { auth->permDbmod || (auth->permLengthvote && !global_settings->{lockdown_edit}) }

sub opts {
    my($mode) = @_;
    tableopts
        date     => { name => 'Date',   sort_id => 0, sort_sql => 'l.date', sort_default => 'desc' },
        length   => { name => 'Time',   sort_id => 1, sort_sql => 'l.length' },
        speed    => { name => 'Speed',  sort_id => 2, sort_sql => 'l.speed ?o, l.length' },
        $mode ne 'u' ? (
        username => { name => 'User',   sort_id => 3, sort_sql => 'u.username' } ) : (),
        $mode ne 'v' ? (
        title    => { name => 'Title',  sort_id => 4, sort_sql => 'v.title' } ) : ()
}
my %TABLEOPTS = map +($_, opts $_), '', 'v', 'u';


sub listing_ {
    my($opt, $count, $list, $mode) = @_;

    my sub url { '?'.query_encode %$opt, @_ }

    if(auth->permDbmod) {
        form_ method => 'post', action => '/lengthvotes-edit';
        input_ type => 'hidden', class => 'hidden', name => 'url', value => tuwf->reqPath.tuwf->reqQuery, undef;
    }

    paginate_ \&url, $opt->{p}, [$count, $opt->{s}->results], 't';
    div_ class => 'mainbox browse lengthlist', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub { txt_ 'Date';   sortable_ 'date', $opt, \&url };
                td_ class => 'tc2', sub { txt_ 'User';   sortable_ 'username', $opt, \&url } if $mode ne 'u';
                td_ class => 'tc2', sub { txt_ 'Title';  sortable_ 'title', $opt, \&url } if $mode ne 'v';
                td_ class => 'tc3', sub { txt_ 'Time';   sortable_ 'length', $opt, \&url };
                td_ class => 'tc4', sub { txt_ 'Speed';  sortable_ 'speed', $opt, \&url };
                td_ class => 'tc5', 'Rel';
                td_ class => 'tc6', 'Notes';
                td_ class => 'tc7', sub {
                    input_ type => 'submit', class => 'submit', value => 'Update', undef;
                } if auth->permDbmod;
            } };
            tr_ sub {
                td_ class => 'tc1', fmtdate $_->{date};
                td_ class => 'tc2', sub { user_ $_ } if $mode ne 'u';
                td_ class => 'tc2', sub {
                    a_ href => "/$_->{vid}", title => $_->{original}||$_->{title}, $_->{title};
                } if $mode ne 'v';
                td_ class => 'tc3'.($_->{ignore}?' grayedout':''), sub { vnlength_ $_->{length} };
                td_ class => 'tc4'.($_->{ignore}?' grayedout':''), ['Slow','Normal','Fast']->[$_->{speed}];
                td_ class => 'tc5', sub { a_ href => "/$_->{rid}", $_->{rid} };
                td_ class => 'tc6', sub { lit_ bb_format $_->{notes}, inline => 1 };
                td_ class => 'tc7', sub {
                    select_ name => "$_->{vid}-$_->{uid}", sub {
                        option_ value => '', '--';
                        option_ value => 's0', 'slow';
                        option_ value => 's1', 'normal';
                        option_ value => 's2', 'fast';
                        option_ value => 'ign', 'ignore' if !$_->{ignore};
                        option_ value => 'noign', 'unignore' if $_->{ignore};
                    };
                } if auth->permDbmod;
            } for @$list;
        };
    };
    paginate_ \&url, $opt->{p}, [$count, $opt->{s}->results], 'b';

    end_ 'form' if auth->permDbmod;
}


sub stats_ {
    my($o) = @_;
    my $stats = tuwf->dbAlli('
        SELECT speed, count(*) as count, avg(l.length) as avg
             , stddev_pop(l.length::real)::int as stddev
             , percentile_cont(', \0.5, ') WITHIN GROUP (ORDER BY l.length) AS median
          FROM vn_length_votes l
          LEFT JOIN users u ON u.id = l.uid
         WHERE u.perm_lengthvote IS DISTINCT FROM false AND NOT l.ignore AND l.vid =', \$o->{id}, '
         GROUP BY GROUPING SETS ((speed),()) ORDER BY speed'
    );

    table_ style => 'margin: 0 auto', sub {
        thead_ sub { tr_ sub {
                td_ 'Speed';
                td_ 'Median';
                td_ 'Average';
                td_ 'Stddev';
                td_ '# Votes';
            } };
        tr_ sub {
            td_ ['Slow', 'Normal', 'Fast', 'Total']->[$_->{speed}//3];
            td_ sub { vnlength_ $_->{median} };
            td_ sub { vnlength_ $_->{avg} };
            td_ sub { vnlength_ $_->{stddev} if $_->{stddev} };
            td_ $_->{count};
        } for @$stats;
    };
}


TUWF::get qr{/(?:(?<thing>$RE{vid}|$RE{uid})/)?lengthvotes}, sub {
    my $thing = tuwf->capture('thing');
    my $o = $thing && dbobj $thing;
    return tuwf->resNotFound if $thing && (!$o->{id} || $o->{entry_hidden});
    my $mode = !$thing ? '' : $o->{id} =~ /^v/ ? 'v' : 'u';

    my $opt = tuwf->validate(get =>
        p => { page => 1 },
        s => { tableopts => $TABLEOPTS{$mode} },
    )->data;

    my $where = sql_and $mode ? sql($mode eq 'v' ? 'l.vid =' : 'l.uid =', \$o->{id}) : ();
    my $count = tuwf->dbVali('SELECT COUNT(*) FROM vn_length_votes l WHERE', $where);

    my $lst = tuwf->dbPagei({results => $opt->{s}->results, page => $opt->{p}},
      'SELECT l.uid, l.vid, l.length, l.speed, l.notes, l.rid, ', sql_totime('l.date'), 'AS date, l.ignore OR u.perm_lengthvote IS NOT DISTINCT FROM false AS ignore',
              $mode ne 'u' ? (', ', sql_user()) : (),
              $mode ne 'v' ? ', v.title, v.original' : (), '
         FROM vn_length_votes l
         LEFT JOIN users u ON u.id = l.uid',
         $mode ne 'v' ? 'JOIN vn v ON v.id = l.vid' : (),
       'WHERE', $where,
       'ORDER BY', $opt->{s}->sql_order(),
    );

    my $title = 'Length votes'.($mode ? ($mode eq 'v' ? ' for ' : ' by ').$o->{title} : '');
    framework_ title => $title, dbobj => $o, sub {
        div_ class => 'mainbox', sub {
            h1_ $title;
            p_ 'Nothing to list. :(' if !@$lst;
            stats_ $o if $mode eq 'v' && @$lst;
        };
        listing_ $opt, $count, $lst, $mode if @$lst;
    };
};


TUWF::post '/lengthvotes-edit', sub {
    return tuwf->resDenied if !auth->permDbmod || !samesite;

    for my $k (tuwf->reqPosts) {
        next if $k !~ /^(?<vid>$RE{vid})-(?<uid>$RE{uid})$/;
        my $where = { vid => $+{vid}, uid => $+{uid} };
        my $act = tuwf->reqPost($k);
        next if !$act;
        warn "$act $where->{vid} $where->{uid}\n";
        tuwf->dbExeci('UPDATE vn_length_votes SET ignore = true WHERE', $where) if $act eq 'ign';
        tuwf->dbExeci('UPDATE vn_length_votes SET ignore = false WHERE', $where) if $act eq 'noign';
        tuwf->dbExeci('UPDATE vn_length_votes SET speed = 0 WHERE', $where) if $act eq 's0';
        tuwf->dbExeci('UPDATE vn_length_votes SET speed = 1 WHERE', $where) if $act eq 's1';
        tuwf->dbExeci('UPDATE vn_length_votes SET speed =', \2, 'WHERE', $where) if $act eq 's2';
    }
    tuwf->resRedirect(tuwf->reqPost('url'), 'post');
};


our $LENGTHVOTE = form_compile any => {
    uid    => { vndbid => 'u' },
    vid    => { vndbid => 'v' },
    vote   => { type => 'hash', required => 0, keys => {
        rid    => { vndbid => 'r' },
        length => { uint => 1, range => [1,32767] },
        speed  => { uint => 1, enum => [0,1,2] },
        notes  => { required => 0, default => '' },
    } },
};

elm_api VNLengthVote => undef, $LENGTHVOTE, sub {
    my($data) = @_;
    return elm_Unauth if !can_vote() || $data->{uid} ne auth->uid;
    my %where = ( uid => $data->{uid}, vid => $data->{vid} );
    tuwf->dbExeci('DELETE FROM vn_length_votes WHERE', \%where) if !$data->{vote};
    tuwf->dbExeci(
        'INSERT INTO vn_length_votes', { %where, $data->{vote}->%* },
        'ON CONFLICT (uid, vid) DO UPDATE SET', $data->{vote}
    ) if $data->{vote};
    return elm_Success;
};

1;
