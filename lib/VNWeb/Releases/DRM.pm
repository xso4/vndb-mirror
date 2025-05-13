package VNWeb::Releases::DRM;

use VNWeb::Prelude;
use FU::Util 'uri_escape';

FU::get '/r/drm', sub {
    my $opt = fu->query(
        n => { onerror => '' },
        s => { onerror => '' },
        t => { onerror => undef, enum => [0,1,2] },
        u => { anybool => 1 },
    );
    my $where = AND
        $opt->{s} ? SQL 'name ILIKE', '%'.sql_like($opt->{s}).'%' : (),
        defined $opt->{t} ? SQL 'state =', $opt->{t} : ();

    my $lst = fu->SQL('
        SELECT id, state, name, description, c_ref, ', RAW(join ', ', keys %DRM_PROPERTY), '
          FROM drm
         WHERE', $where, $opt->{u} ? () : 'AND c_ref > 0',
        'ORDER BY c_ref DESC
    ')->allh;
    my $missing = $opt->{u} ? 0 : fu->SQL('SELECT COUNT(*) FROM drm WHERE', $where, 'AND c_ref = 0')->val;

    framework_ title => 'List of DRM implementations', sub {
        article_ sub {
            h1_ 'List of DRM implementations';
            form_ action => '/r/drm', method => 'get', sub {
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
                    span_ class => 'strikethrough', $d->{name} if $d->{state} == 2;
                    txt_ $d->{name} if $d->{state} != 2;
                    a_ href => '/r?f='.FU::Validate->compile({advsearch => 'r'})->validate(['drm','=',$d->{name}])->enc_query, " ($d->{c_ref})";
                    b_ ' (new)' if $d->{state} == 0;
                    a_ href => "/r/drm/edit/$d->{id}?ref=".uri_escape(query_encode($opt)), ' edit' if auth->permDbmod;
                };
                my @prop = grep $d->{$_}, keys %DRM_PROPERTY;
                p_ sub {
                    join_ ' ', sub {
                        abbr_ class => "icon-drm-$_", title => $DRM_PROPERTY{$_}, '';
                        txt_ $DRM_PROPERTY{$_};
                    }, @prop;
                    if (!@prop) {
                        abbr_ class => 'icon-drm-free', title => 'DRM-free', '';
                        txt_ 'DRM-free';
                    }
                };
                div_ sub { lit_ bb_format $d->{description} if $d->{description} };
            } for @$lst;
            p_ class => 'center', sub {
                txt_ "$missing unused DRM type(s) not shown. ";
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
    map +($_,{anybool=>1}), keys %DRM_PROPERTY
};


sub info($id) {
    fu->SQL('
        SELECT id, state, name, description,', RAW(join(', ', keys %DRM_PROPERTY)), '
          FROM drm WHERE id =', $id
    )->rowh;
}

FU::get qr{/r/drm/edit/(0|$RE{num})}, sub($id) {
    fu->denied if !auth->permDbmod;
    my $d = info $id;
    fu->notfound if !defined $d->{id};
    $d->{ref} = fu->query(ref => { onerror => '' });
    framework_ title => "Edit DRM: $d->{name}", sub {
        div_ widget(DRMEdit => $FORM, $d), '';
    };
};

js_api DRMEdit => $FORM, sub($data) {
    fu->denied if !auth->permDbmod;
    my $d = info delete $data->{id};
    fu->notfound if !defined $d->{id};
    my $ref = delete $data->{ref};

    return 'Duplicate DRM name' if fu->SQL('SELECT 1 FROM drm WHERE id <>', $d->{id}, 'AND name =', $d->{name})->val;

    fu->SQL('UPDATE drm', SET($data), 'WHERE id =', $d->{id})->exec;

    my @diff = grep $d->{$_} ne $data->{$_}, qw/state name description/, keys %DRM_PROPERTY;
    auth->audit(undef, 'drm edit', join '; ', map "$_: $d->{$_} -> $data->{$_}", @diff) if @diff;
    +{ _redir => "/r/drm?$ref" };
};

1;
