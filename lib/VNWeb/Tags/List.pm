# XXX: Also used for the trait listing

package VNWeb::Tags::List;

use VNWeb::Prelude;


sub listing_ {
    my($type, $opt, $list, $count) = @_;

    my sub url { '?'.query_encode %$opt, @_ }

    paginate_ \&url, $opt->{p}, [$count, 50], 't';
    div_ class => 'mainbox browse taglist', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc1', sub { txt_ 'Created'; sortable_ 'added', $opt, \&url };
                td_ class => 'tc2', sub { txt_ $type eq 'g' ? 'VNs' : 'Chars'; sortable_ 'items', $opt, \&url };
                td_ class => 'tc3', sub { txt_ 'Name';    sortable_ 'name',  $opt, \&url };
            } };
            tr_ sub {
                td_ class => 'tc1', fmtage $_->{added};
                td_ class => 'tc2', $_->{c_items}||'-';
                td_ class => 'tc3', sub {
                    b_ class => 'grayedout', "$_->{group} / " if $_->{group};
                    a_ href => "/$type$_->{id}", $_->{name};
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


TUWF::get qr{/(?<type>[gi])/list}, sub {
    my $type = tuwf->capture('type');
    my $opt = tuwf->validate(get =>
        s => { onerror => 'name', enum => ['added', 'name', 'vns', 'items'] },
        o => { onerror => 'a', enum => ['a', 'd'] },
        p => { upage => 1 },
        t => { onerror => undef, enum => [ -1..2 ] },
        a => { undefbool => 1 },
        b => { undefbool => 1 },
        q => { onerror => '' },
    )->data;
    $opt->{s} = 'items' if $opt->{s} eq 'vns';
    $opt->{t} = undef if $opt->{t} && $opt->{t} == -1; # for legacy URLs

    my $qs = $opt->{q} && '%'.sql_like($opt->{q}).'%';
    my $where = sql_and
        defined $opt->{t} ? sql 't.state =', \$opt->{t} : (),
        defined $opt->{a} ? sql 't.applicable =', \$opt->{a} : (),
        defined $opt->{b} ? sql 't.searchable =', \$opt->{b} : (),
        $type eq 'g' ? (
            $opt->{q} ? sql 't.name ILIKE', \$qs, 'OR t.id IN(SELECT tag FROM tags_aliases WHERE alias ILIKE', \$qs, ')' : ()
        ) : (
            $opt->{q} ? sql 't.name ILIKE', \$qs, 'OR t.alias ILIKE', \$qs : ()
        );

    my $table = $type eq 'g' ? 'tags' : 'traits';
    my $count = tuwf->dbVali("SELECT COUNT(*) FROM $table t WHERE", $where);
    my $list = tuwf->dbPagei({ results => 50, page => $opt->{p} },'
        SELECT t.id, t.name, t.state, t.searchable, t.applicable, t.c_items,', sql_totime('t.added'), "as added
          FROM $table t
         WHERE ", $where, '
         ORDER BY', {qw|added id  name name  items c_items|}->{$opt->{s}}, {qw|a ASC d DESC|}->{$opt->{o}}, ', id'
    );

    enrich_merge id => 'SELECT t.id, g.name AS "group" FROM traits t JOIN traits g ON g.id = t."group" WHERE t.id IN', $list if $type eq 'i';

    framework_ title => "Browse $table", index => 1, sub {
        div_ class => 'mainbox', sub {
            h1_ "Browse $table";
            form_ action => "/$type/list", method => 'get', sub {
                searchbox_ $type => $opt->{q};
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
        listing_ $type, $opt, $list, $count if $count;
    };
};

1;
