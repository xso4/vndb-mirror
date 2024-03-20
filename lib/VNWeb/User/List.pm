package VNWeb::User::List;

use VNWeb::Prelude;


sub listing_ {
    my($opt, $list, $count) = @_;

    my sub url { '?'.query_encode %$opt, @_ }

    paginate_ \&url, $opt->{p}, [$count, 50], 't';
    article_ class => 'browse userlist', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub { txt_ 'Username';   sortable_ 'username',   $opt, \&url };
                td_ class => 'tc2', sub { txt_ 'Registered'; sortable_ 'registered', $opt, \&url };
                td_ class => 'tc3', sub { txt_ 'VNs';        sortable_ 'vns',        $opt, \&url };
                td_ class => 'tc4', sub { txt_ 'Votes';      sortable_ 'votes',      $opt, \&url };
                td_ class => 'tc5', sub { txt_ 'Wishlist';   sortable_ 'wish',       $opt, \&url };
                td_ class => 'tc6', sub { txt_ 'Edits';      sortable_ 'changes',    $opt, \&url };
                td_ class => 'tc7', sub { txt_ 'Tags';       sortable_ 'tags',       $opt, \&url };
                td_ class => 'tc8', sub { txt_ 'Images';     sortable_ 'images',     $opt, \&url };
            } };
            tr_ sub {
                my $l = $_;
                td_ class => 'tc1', sub { user_ $l };
                td_ class => 'tc2', fmtdate $l->{registered};
                td_ class => 'tc3', sub {
                    txt_ '0' if !$l->{c_vns};
                    a_ href => "/$l->{user_id}/ulist?vnlist=1", $l->{c_vns} if $l->{c_vns};
                };
                td_ class => 'tc4', sub {
                    txt_ '0' if !$l->{c_votes};
                    a_ href => "/$l->{user_id}/ulist?votes=1", $l->{c_votes} if $l->{c_votes};
                };
                td_ class => 'tc5', sub {
                    txt_ '0' if !$l->{c_wish};
                    a_ href => "/$l->{user_id}/ulist?wishlist=1", $l->{c_wish} if $l->{c_wish};
                };
                td_ class => 'tc6', sub {
                    txt_ '-' if !$l->{c_changes};
                    a_ href => "/$l->{user_id}/hist", $l->{c_changes} if $l->{c_changes};
                };
                td_ class => 'tc7', sub {
                    txt_ '-' if !$l->{c_tags};
                    a_ href => "/g/links?u=$l->{user_id}", $l->{c_tags} if $l->{c_tags};
                };
                td_ class => 'tc8', sub {
                    txt_ '-' if !$l->{c_imgvotes};
                    a_ href => "/img/list?u=$l->{user_id}", $l->{c_imgvotes} if $l->{c_imgvotes};
                };
            } for @$list;
        };
    };
    paginate_ \&url, $opt->{p}, [$count, 50], 'b';
}


TUWF::get qr{/u/(?<char>[0a-z]|all)}, sub {
    my $char = tuwf->capture('char');

    my $opt = tuwf->validate(get =>
        p => { upage => 1 },
        s => { onerror => 'registered', enum => [qw[username registered vns votes wish changes tags images]] },
        o => { onerror => 'd',          enum => [qw[a d]] },
        q => { onerror => '' },
    )->data;

    my @where = (
        'username IS NOT NULL',
        auth->permUsermod ? () : 'email_confirmed',
        $char eq 'all' ? () : sql('match_firstchar(username, ', \$char, ')'),
        $opt->{q} ? sql_or(
            auth->permUsermod && $opt->{q} =~ /@/ ? sql('id IN(SELECT uid FROM user_emailtoid(', \$opt->{q}, '))') : (),
            $opt->{q} =~ /^u?$RE{num}$/ ? sql 'id =', \"u$1" : (),
            $opt->{q} =~ /@/ ? () : sql('username ILIKE', \('%'.sql_like($opt->{q}).'%')),
        ) : ()
    );

    my $list = tuwf->dbPagei({ results => 50, page => $opt->{p} },
        'SELECT', sql_user(), ',', sql_totime('registered'), 'as registered, c_vns, c_votes, c_wish, c_changes, c_tags, c_imgvotes
           FROM users u
          WHERE', sql_and(@where),
         'ORDER BY', {
                  username   => 'lower(username)',
                  registered => 'id',
                  vns        => 'c_vns',
                  votes      => 'c_votes',
                  wish       => 'c_wish',
                  changes    => 'c_changes',
                  tags       => 'c_tags',
                  images     => 'c_imgvotes',
                }->{$opt->{s}}, $opt->{o} eq 'd' ? 'DESC' : 'ASC'
    );
    state $totalusers = tuwf->dbVal('SELECT count(*) FROM users');
    my $count = @where ? tuwf->dbVali('SELECT count(*) FROM users WHERE', sql_and @where) : $totalusers;

    framework_ title => 'Browse users', sub {
        article_ sub {
            h1_ 'Browse users';
            form_ action => '/u/all', method => 'get', sub {
                fieldset_ class => 'search', sub {
                    input_ type => 'text', name => 'q', id => 'q', class => 'text', value => $opt->{q}//'';
                    input_ type => 'submit', class => 'submit', value => 'Search!';
                }
            };
            p_ class => 'browseopts', sub {
                a_ href => "/u/$_", $_ eq $char ? (class => 'optselected') : (), $_ eq 'all' ? 'ALL' : $_ ? uc $_ : '#'
                    for ('all', 'a'..'z', 0);
            };
            b_ 'The given email address is on the opt-out list.'
              if auth->permUsermod && $opt->{q} && $opt->{q} =~ /@/ && tuwf->dbVali('SELECT email_optout_check(', \$opt->{q}, ')');
        };
        listing_ $opt, $list, $count if $count;
    };
};

1;
