package VNWeb::VN::Length;

use VNWeb::Prelude;

sub opts {
    my($vn) = @_;
    tableopts
        date     => { name => 'Date',   sort_id => 0, sort_sql => 'l.date', sort_default => 'desc' },
        length   => { name => 'Time',   sort_id => 1, sort_sql => 'l.length' },
        speed    => { name => 'Speed',  sort_id => 2, sort_sql => 'l.speed ?o, l.length' },
        $vn ? (
        username => { name => 'User',   sort_id => 3, sort_sql => 'u.username' },
        ) : (
        title    => { name => 'Title',  sort_id => 4, sort_sql => 'v.title' },
        );
}
my $TABLEOPTS_U = opts 0;
my $TABLEOPTS_V = opts 1;


sub listing_ {
    my($opt, $count, $list, $vn) = @_;

    my sub url { '?'.query_encode %$opt, @_ }

    paginate_ \&url, $opt->{p}, [$count, $opt->{s}->results], 't';
    div_ class => 'mainbox browse lengthlist', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub { txt_ 'Date';   sortable_ 'date', $opt, \&url };
                td_ class => 'tc2', sub { txt_ 'User';   sortable_ 'username', $opt, \&url } if $vn;
                td_ class => 'tc2', sub { txt_ 'Title';  sortable_ 'title', $opt, \&url } if !$vn;
                td_ class => 'tc3', sub { txt_ 'Time';   sortable_ 'length', $opt, \&url };
                td_ class => 'tc4', sub { txt_ 'Speed';  sortable_ 'speed', $opt, \&url };
                td_ class => 'tc5', 'Rel';
                td_ class => 'tc6', 'Notes';
            } };
            tr_ sub {
                td_ class => 'tc1', fmtdate $_->{date};
                td_ class => 'tc2', sub { user_ $_ } if $vn;
                td_ class => 'tc2', sub {
                    a_ href => "/$_->{vid}", title => $_->{original}||$_->{title}, $_->{title};
                } if !$vn;
                td_ class => 'tc3', sub { vnlength_ $_->{length} };
                td_ class => 'tc4', ['Slow','Normal','Fast']->[$_->{speed}];
                td_ class => 'tc5', sub { a_ href => "/$_->{rid}", $_->{rid} };
                td_ class => 'tc6', sub { lit_ bb_format $_->{notes}, inline => 1 };
            } for @$list;
        };
    };
    paginate_ \&url, $opt->{p}, [$count, $opt->{s}->results], 'b';
}


TUWF::get qr{/(?<thing>$RE{vid}|$RE{uid})/lengthvotes}, sub {
    my $o = dbobj tuwf->capture('thing');
    return tuwf->resNotFound if !$o->{id} || $o->{entry_hidden};
    my $vn = $o->{id} =~ /^v/;

    my $opt = tuwf->validate(get =>
        p => { page => 1 },
        s => { tableopts => $vn ? $TABLEOPTS_V : $TABLEOPTS_U },
    )->data;

    my $where = sql_and
        $vn ? 'NOT EXISTS(SELECT 1 FROM users WHERE users.id = l.uid AND NOT perm_lengthvote)' : (),
        sql($vn ? 'l.vid =' : 'l.uid =', \$o->{id});
    my $count = tuwf->dbVali('SELECT COUNT(*) FROM vn_length_votes l WHERE', $where);

    my $lst = tuwf->dbPagei({results => $opt->{s}->results, page => $opt->{p}},
      'SELECT l.uid, l.vid, l.length, l.speed, l.notes, l.rid, ', sql_totime('l.date'), 'AS date, ',
              $vn ? sql_user() : 'v.title, v.original', '
         FROM vn_length_votes l',
         $vn ? 'LEFT JOIN users u ON u.id = l.uid'
             : 'JOIN vn v ON v.id = l.vid',
       'WHERE', $where,
       'ORDER BY', $opt->{s}->sql_order(),
    );

    my $title = 'Length votes '.($vn ? 'for ' : 'by ').$o->{title};
    framework_ title => $title, dbobj => $o, sub {
        div_ class => 'mainbox', sub {
            h1_ $title;
            p_ 'Nothing to list. :(' if !@$lst;
        };
        listing_ $opt, $count, $lst, $vn if @$lst;
    };
};

1;
