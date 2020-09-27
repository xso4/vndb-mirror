package VNWeb::Tags::List;

use VNWeb::Prelude;


sub listing_ {
    my($opt, $list, $count) = @_;

    my sub url { '?'.query_encode %$opt, @_ }

    paginate_ \&url, $opt->{p}, [$count, 50], 't';
    div_ class => 'mainbox browse taglist', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub { txt_ 'Created'; sortable_ 'added', $opt, \&url };
                td_ class => 'tc2', sub { txt_ 'VNs';     sortable_ 'vns',   $opt, \&url };
                td_ class => 'tc3', sub { txt_ 'Name';    sortable_ 'name',  $opt, \&url };
            } };
            tr_ sub {
                td_ class => 'tc1', fmtage $_->{added};
                td_ class => 'tc2', $_->{c_items}||'-';
                td_ class => 'tc3', sub {
                    a_ href => "/g$_->{id}", $_->{name};
                    join_ ',', sub { b_ class => 'grayedout', ' '.$_ },
                        $_->{state} == 0 ? 'awaiting moderation' : $_->{state} == 1 ? 'deleted' : (),
                        !$_->{applicable} ? 'not applicable' : (),
                        !$_->{searchable} ? 'not searchable' : ();
                };
            } for @$list;
        };
    };
    paginate_ \&url, $opt->{p}, [$count, 50], 'b';
}


TUWF::get qr{/g/list}, sub {
    my $opt = tuwf->validate(get =>
        s => { onerror => 'name', enum => ['added', 'name', 'vns'] },
        o => { onerror => 'a', enum => ['a', 'd'] },
        p => { upage => 1 },
        t => { onerror => undef, enum => [ -1..2 ] },
        a => { undefbool => 1 },
        b => { undefbool => 1 },
        q => { onerror => '' },
    )->data;

    $opt->{t} = undef if $opt->{t} && $opt->{t} == -1; # for legacy URLs

    my $qs = $opt->{q} && '%'.sql_like($opt->{q}).'%';
    my $where = sql_and
        defined $opt->{t} ? sql 't.state =', \$opt->{t} : (),
        defined $opt->{a} ? sql 't.applicable =', \$opt->{a} : (),
        defined $opt->{b} ? sql 't.searchable =', \$opt->{b} : (),
        $opt->{q} ? sql 't.name ILIKE', \$qs, 'OR t.id IN(SELECT tag FROM tags_aliases WHERE alias ILIKE', \$qs, ')' : ();

    my $count = tuwf->dbVali('SELECT COUNT(*) FROM tags t WHERE', $where);
    my $list = tuwf->dbPagei({ results => 50, page => $opt->{p} },'
        SELECT t.id, t.name, t.state, t.searchable, t.applicable, t.cat, t.c_items,', sql_totime('t.added'), 'as added
          FROM tags t
         WHERE ', $where, '
         ORDER BY', {qw|added id  name name  vns c_items|}->{$opt->{s}}, {qw|a ASC d DESC|}->{$opt->{o}}, ', id'
    );

    framework_ title => 'Browse tags', index => 1, sub {
        div_ class => 'mainbox', sub {
            h1_ 'Browse tags';
            form_ action => '/g/list', method => 'get', sub {
                searchbox_ g => $opt->{q};
            };
            my sub opt_ {
                my($k,$v,$lbl) = @_;
                a_ href => '?'.query_encode(%$opt,p=>undef,$k=>$v), defined $opt->{$k} eq defined $v && (!defined $v || $opt->{$k} == $v) ? (class => 'optselected') : (), $lbl;
            }
            p_ class => 'browseopts', sub {
                opt_ t => undef, 'All';
                opt_ t => 0,     'Awaiting moderation';
                opt_ t => 1,     'Deleted';
                opt_ t => 2,     'Accepted';
            };
            p_ class => 'browseopts', sub {
                opt_ a => undef, 'All';
                opt_ a => 0,     'Not applicable';
                opt_ a => 1,     'Applicable';
            };
            p_ class => 'browseopts', sub {
                opt_ b => undef, 'All';
                opt_ b => 0,     'Not searchable';
                opt_ b => 1,     'Searchable';
            };
        };
        listing_ $opt, $list, $count if $count;
    };
};

1;
