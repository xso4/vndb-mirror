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
            } };
            tr_ sub {
                td_ class => 'tc1', fmtdate $_->{date};
                td_ class => 'tc2', sub { user_ $_ } if $mode ne 'u';
                td_ class => 'tc2', sub {
                    a_ href => "/$_->{vid}", title => $_->{original}||$_->{title}, $_->{title};
                } if $mode ne 'v';
                td_ class => 'tc3', sub { vnlength_ $_->{length} };
                td_ class => 'tc4', ['Slow','Normal','Fast']->[$_->{speed}];
                td_ class => 'tc5', sub { a_ href => "/$_->{rid}", $_->{rid} };
                td_ class => 'tc6', sub { lit_ bb_format $_->{notes}, inline => 1 };
            } for @$list;
        };
    };
    paginate_ \&url, $opt->{p}, [$count, $opt->{s}->results], 'b';
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

    my $where = sql_and
        $mode ne 'u' ? 'NOT EXISTS(SELECT 1 FROM users WHERE users.id = l.uid AND NOT perm_lengthvote)' : (),
        $mode ? sql($mode eq 'v' ? 'l.vid =' : 'l.uid =', \$o->{id}) : ();
    my $count = tuwf->dbVali('SELECT COUNT(*) FROM vn_length_votes l WHERE', $where);

    my $lst = tuwf->dbPagei({results => $opt->{s}->results, page => $opt->{p}},
      'SELECT l.uid, l.vid, l.length, l.speed, l.notes, l.rid, ', sql_totime('l.date'), 'AS date',
              $mode ne 'u' ? (', ', sql_user()) : (),
              $mode ne 'v' ? ', v.title, v.original' : (), '
         FROM vn_length_votes l',
         $mode ne 'u' ? 'LEFT JOIN users u ON u.id = l.uid' : (),
         $mode ne 'v' ? 'JOIN vn v ON v.id = l.vid' : (),
       'WHERE', $where,
       'ORDER BY', $opt->{s}->sql_order(),
    );

    my $title = 'Length votes'.($mode ? ($mode eq 'v' ? ' for ' : ' by ').$o->{title} : '');
    framework_ title => $title, dbobj => $o, sub {
        div_ class => 'mainbox', sub {
            h1_ $title;
            p_ 'Nothing to list. :(' if !@$lst;
        };
        listing_ $opt, $count, $lst, $mode if @$lst;
    };
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
