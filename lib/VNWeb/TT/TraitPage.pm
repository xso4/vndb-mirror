package VNWeb::TT::TraitPage;

use VNWeb::Prelude;
use VNWeb::Filters;
use VNWeb::AdvSearch;
use VNWeb::Images::Lib;
use VNWeb::TT::Lib 'tree_', 'parents_';


sub rev_ {
    my($t) = @_;
    sub enrich_item {
        enrich_merge parent => 'SELECT id AS parent, name FROM traits WHERE id IN', $_[0]{parents};
        $_[0]{parents} = [ sort { $a->{name} cmp $b->{name} || $a->{parent} <=> $b->{parent} } $_[0]{parents}->@* ];
    }
    enrich_item $t;
    revision_ $t, \&enrich_item,
        [ name         => 'Name'           ],
        [ alias        => 'Aliases'        ],
        [ description  => 'Description'    ],
        [ sexual       => 'Sexual content',fmt => 'bool' ],
        [ searchable   => 'Searchable',    fmt => 'bool' ],
        [ applicable   => 'Applicable',    fmt => 'bool' ],
        [ defaultspoil => 'Default spoiler level' ],
        [ gorder       => 'Sort order'     ],
        [ parents      => 'Parent traits', fmt => sub { a_ href => "/$_->{parent}", $_->{name}; txt_ ' (primary)' if $_->{main} } ];
}


sub infobox_ {
    my($t) = @_;

    p_ class => 'mainopts', sub {
        a_ href => "/$t->{id}/add", 'Create child trait';
    } if !$t->{hidden} && can_edit i => {};
    h1_ "Trait: $t->{name}";
    debug_ $t;

    parents_ i => $t;

    div_ class => 'description', sub {
        lit_ bb_format $t->{description};
    } if $t->{description};

    my @prop = (
        !$t->{sexual}    ? () : 'Indicates sexual content.',
        $t->{searchable} ? () : 'Not searchable.',
        $t->{applicable} ? () : 'Can not be directly applied to characters.',
    );
    p_ class => 'center', sub {
        strong_ 'Properties';
        br_;
        join_ \&br_, sub { txt_ $_ }, @prop;
    } if @prop;

    p_ class => 'center', sub {
        strong_ 'Aliases';
        br_;
        join_ \&br_, sub { txt_ $_ }, split /\n/, $t->{alias};
    } if $t->{alias};
}


sub chars_ {
    my($t) = @_;

    my $opt = tuwf->validate(get =>
        p => { upage => 1 },
        f => { advsearch_err => 'c' },
        m => { onerror => [auth->pref('spoilers')||0], type => 'array', scalar => 1, minlength => 1, values => { enum => [0..2] } },
        l => { onerror => [''], type => 'array', scalar => 1, minlength => 1, values => { anybool => 1 } },
        fil => { required => 0 },
        s => { tableopts => $VNWeb::Chars::List::TABLEOPTS },
    )->data;
    $opt->{m} = $opt->{m}[0];
    $opt->{l} = $opt->{l}[0];

    # URL compatibility with old filters
    if(!$opt->{f}->{query} && $opt->{fil}) {
        my $q = eval {
            my $f = filter_parse c => $opt->{fil};
            # Old URLs often had the trait ID as part of the filter, let's remove that.
            $f->{trait_inc} = [ grep "i$_" ne $t->{id}, $f->{trait_inc}->@* ] if $f->{trait_inc};
            delete $f->{trait_inc} if $f->{trait_inc} && !$f->{trait_inc}->@*;
            $f = filter_char_adv $f;
            tuwf->compile({ advsearch => 'c' })->validate(@$f > 1 ? $f : undef)->data;
        };
        return tuwf->resRedirect(tuwf->reqPath().'?'.query_encode(%$opt, fil => undef, f => $q), 'perm') if $q;
    }

    $opt->{f} = advsearch_default 'c' if !$opt->{f}{query} && !defined tuwf->reqGet('f');

    my $where = sql_and
        'NOT c.hidden',
        $opt->{l} ? 'NOT tc.lie' : (),
        sql('tc.tid =', \$t->{id}),
        sql('tc.spoil <=', \$opt->{m}),
        $opt->{f}->sql_where();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = tuwf->dbVali('SELECT count(*) FROM chars c JOIN traits_chars tc ON tc.cid = c.id WHERE', $where);
        $list = $count ? tuwf->dbPagei({results => $opt->{s}->results(), page => $opt->{p}}, '
            SELECT c.id, c.title, c.gender, c.image
              FROM', charst, 'c
              JOIN traits_chars tc ON tc.cid = c.id
             WHERE', $where, '
             ORDER BY c.sorttitle, c.id'
        ) : [];
    } || (($count, $list) = (undef, []));

    VNWeb::Chars::List::enrich_listing $list;
    enrich_image_obj image => $list if !$opt->{s}->rows;
    $time = time - $time;

    form_ action => "/$t->{id}", method => 'get', sub {
        div_ class => 'mainbox', sub {
            h1_ 'Characters';
            p_ class => 'browseopts', sub {
                button_ type => 'submit', name => 'm', value => 0, $opt->{m} == 0 ? (class => 'optselected') : (), 'Hide spoilers';
                button_ type => 'submit', name => 'm', value => 1, $opt->{m} == 1 ? (class => 'optselected') : (), 'Show minor spoilers';
                button_ type => 'submit', name => 'm', value => 2, $opt->{m} == 2 ? (class => 'optselected') : (), 'Spoil me!';
            };
            p_ class => 'browseopts', sub {
                button_ type => 'submit', name => 'l', value => 0, !$opt->{l} ? (class => 'optselected') : (), 'Include lies';
                button_ type => 'submit', name => 'l', value => 1,  $opt->{l} ? (class => 'optselected') : (), 'Exclude lies';
            };
            input_ type => 'hidden', name => 'm', value => $opt->{m};
            $opt->{f}->elm_;
            advsearch_msg_ $count, $time;
        };
        VNWeb::Chars::List::listing_ $opt, $list, $count, 1 if $count;
    };
}


TUWF::get qr{/$RE{irev}}, sub {
    my $t = db_entry tuwf->captures('id', 'rev');
    return tuwf->resNotFound if !$t->{id};

    framework_ index => !$t->{hidden}, title => "Trait: $t->{name}", dbobj => $t, hiddenmsg => 1, sub {
        rev_ $t if tuwf->capture('rev');
        div_ class => 'mainbox', sub { infobox_ $t; };
        tree_ i => $t->{id};
        chars_ $t if $t->{searchable} && !$t->{hidden};
    };
};

1;
