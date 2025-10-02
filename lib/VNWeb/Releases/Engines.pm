package VNWeb::Releases::Engines;
# (Largely a copy of Releases::DRM)

use VNWeb::Prelude;
use FU::Util 'uri_escape';


FU::get '/r/engines', sub {
    my $opt = fu->query(
        n => { onerror => '' },
        s => { onerror => '' },
        m => { onerror => '' },
        t => { onerror => undef, enum => [0,1,2] },
        u => { anybool => 1 },
    );
    my $where = AND
        $opt->{m} ? SQL 'name =', $opt->{m} : (),
        $opt->{s} ? SQL 'name ILIKE', '%'.sql_like($opt->{s}).'%' : (),
        defined $opt->{t} ? SQL 'state =', $opt->{t} : ();

    my $lst = fu->SQL('
        SELECT id, state, name, description, c_ref
          FROM engines
         WHERE', $where, $opt->{u} ? () : 'AND c_ref > 0',
        'ORDER BY c_ref DESC
    ')->allh;
    my $missing = $opt->{u} ? 0 : fu->SQL('SELECT COUNT(*) FROM engines WHERE', $where, 'AND c_ref = 0')->val;

    framework_ title => 'Engine list', sub {
        article_ sub {
            h1_ 'Engine list';
            form_ action => '/r/engines', method => 'get', sub {
                fieldset_ class => 'search', sub {
                    input_ type => 'text', name => 's', id => 's', class => 'text', value => $opt->{s};
                    input_ type => 'submit', class => 'submit', value => 'Search!';
                }
            };
            my sub opt_ {
                my($k,$v,$lbl) = @_;
                a_ href => '?'.query_encode({%$opt,$k=>$v}), defined $opt->{$k} eq defined $v && (!defined $v || $opt->{$k} == $v) ? (class => 'optselected') : (), $lbl;
            }
            p_ class => 'browseopts', sub {
                a_ href => '?'.query_encode({%$opt,t=>undef}), !defined $opt->{t} ? (class => 'optselected') : (), 'All';
                a_ href => '?'.query_encode({%$opt,t=>0}), defined $opt->{t} && $opt->{t} == 0 ? (class => 'optselected') : (), 'New';
                a_ href => '?'.query_encode({%$opt,t=>1}), defined $opt->{t} && $opt->{t} == 1 ? (class => 'optselected') : (), 'Approved';
                a_ href => '?'.query_encode({%$opt,t=>2}), defined $opt->{t} && $opt->{t} == 2 ? (class => 'optselected') : (), 'Deleted';
            };
            my $unused = 0;
            section_ class => 'drmlist', sub {
                my $d = $_;
                h2_ !$d->{c_ref} && !$unused++ ? (id => 'unused') : (), sub {
                    span_ class => 'linethrough', $d->{name} if $d->{state} == 2;
                    txt_ $d->{name} if $d->{state} != 2;
                    a_ href => '/r?f='.FU::Validate->compile({advsearch => 'r'})->validate(['engine','=',$d->{name}])->enc_query, " ($d->{c_ref})";
                    b_ ' (new)' if $d->{state} == 0;
                    a_ href => "/r/engines/edit/$d->{id}?ref=".uri_escape(query_encode($opt)), ' edit' if auth->permDbmod;
                };
                div_ sub { lit_ bb_format $d->{description} if $d->{description} };
            } for @$lst;
            p_ class => 'center', sub {
                txt_ "$missing unused engine(s) not shown. ";
                a_ href => '?'.query_encode({%$opt,u=>1}).'#unused', 'Show all';
            } if $missing;
        };
    };
};


my $FORM = form_compile any => {
    id          => { uint => 1 },
    state       => { uint => 1, range => [0,2] },
    name        => { sl => 1, maxlength => 128 },
    description => { default => '', maxlength => 10240 },
    ref         => { default => '' },
};


FU::get qr{/r/engines/edit/(0|$RE{num})}, sub($id) {
    fu->denied if !auth->permDbmod;
    my $d = fu->sql('SELECT id, state, name, description FROM engines WHERE id = $1', $id)->rowh;
    fu->notfound if !defined $d->{id};
    $d->{ref} = fu->query(ref => { onerror => '' });
    framework_ title => "Edit Engine: $d->{name}", sub {
        div_ widget(EngineEdit => $FORM, $d), '';
    };
};

js_api EngineEdit => $FORM, sub($data) {
    fu->denied if !auth->permDbmod;
    my $d = fu->sql('SELECT id, state, name, description FROM engines WHERE id = $1', delete $data->{id})->rowh;
    fu->notfound if !defined $d->{id};
    my $ref = delete $data->{ref};

    return 'Duplicate engine name' if fu->SQL('SELECT 1 FROM engines WHERE id <>', $d->{id}, 'AND name =', $d->{name})->val;

    fu->SQL('UPDATE engines', SET($data), 'WHERE id =', $d->{id})->exec;

    my @diff = grep $d->{$_} ne $data->{$_}, qw/state name description/;
    auth->audit(undef, 'engine edit', join '; ', map "$_: $d->{$_} -> $data->{$_}", @diff) if @diff;
    +{ _redir => "/r/engines?$ref" };
};


1;
