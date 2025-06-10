package VNWeb::TT::List;

use VNWeb::Prelude;
use VNWeb::TT::Lib 'enrich_group';


sub listing_($type, $opt, $list, $count) {
    my sub url { '?'.query_encode({%$opt, @_}) }

    paginate_ \&url, $opt->{p}, [$count, 50], 't';
    article_ class => 'browse taglist', sub {
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
                    small_ "$_->{group} / " if $_->{group};
                    a_ href => "/$_->{id}", $_->{name};
                    join_ ',', sub { small_ ' '.$_ },
                        !$_->{hidden} ? () : $_->{locked} ? 'deleted' : 'awaiting moderation',
                        !$_->{applicable} ? 'not applicable' : (),
                        !$_->{searchable} ? 'not searchable' : ();
                };
            } for @$list;
        };
    };
    paginate_ \&url, $opt->{p}, [$count, 50], 'b';
}


sub listpage($type) {
    my $opt = fu->query(
        s => { onerror => 'qscore', enum => ['qscore', 'added', 'name', 'vns', 'items'] },
        o => { onerror => 'a', enum => ['a', 'd'] },
        p => { upage => 1 },
        t => { onerror => undef, enum => [ -1..2 ] },
        a => { undefbool => 1 },
        b => { undefbool => 1 },
        q => { searchquery => 1 },
    );
    $opt->{s} = 'items' if $opt->{s} eq 'vns';
    $opt->{s} = 'name' if $opt->{s} eq 'qscore' && !$opt->{q};
    $opt->{t} = undef if $opt->{t} && $opt->{t} == -1; # for legacy URLs

    my $where = AND
        !defined $opt->{t} ? () :
            $opt->{t} == 0 ? 'hidden AND NOT locked' :
            $opt->{t} == 1 ? 'hidden AND locked' : 'NOT hidden',
        defined $opt->{a} ? SQL 'applicable =', $opt->{a} : (),
        defined $opt->{b} ? SQL 'searchable =', $opt->{b} : ();

    my $table = $type eq 'g' ? 'tags' : 'traits';
    my $count = fu->SQL('SELECT COUNT(*) FROM', RAW $table, 't WHERE', AND $where, $opt->{q}->WHERE($type, 't.id'))->val;
    my $list = fu->SQL('
        SELECT t.id, name, hidden, locked, searchable, applicable, c_items, added
          FROM', RAW $table, 't', $opt->{q}->JOIN($type, 't.id'), '
         WHERE', $where, '
         ORDER BY', RAW {qscore => '10 - sc.score', qw|added t.id  name name  items c_items|}->{$opt->{s}}, RAW {qw|a ASC d DESC|}->{$opt->{o}}, ', id
         LIMIT 50 OFFSET', 50*($opt->{p}-1)
    )->allh;

    enrich_group $type, $list;

    framework_ title => "Browse $table", index => 1, sub {
        article_ sub {
            h1_ "Browse $table";
            form_ action => "/$type/list", method => 'get', sub {
                searchbox_ $type => $opt->{q};
            };
            my sub opt_ {
                my($k,$v,$lbl) = @_;
                a_ href => '?'.query_encode({%$opt,p=>undef,$k=>$v}), defined $opt->{$k} eq defined $v && (!defined $v || $opt->{$k} == $v) ? (class => 'optselected') : (), $lbl;
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
FU::get '/g/list', sub { listpage 'g' };
FU::get '/i/list', sub { listpage 'i' };

1;
