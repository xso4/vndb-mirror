package VNWeb::TT::TraitPage;

use VNWeb::Prelude;
use VNWeb::Filters;
use VNWeb::AdvSearch;
use VNWeb::Images::Lib;
use VNWeb::TT::Lib 'tree_', 'parents_';


sub rev_($t) {
    revision_ $t, sub {},
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


sub infobox_($t) {
    itemmsg_ $t;
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


sub chars_($t) {
    my $opt = fu->query(
        p => { upage => 1 },
        f => { advsearch_err => 'c' },
        m => { onerror => auth->pref('spoilers')||0, accept_array => 'first', enum => [0..2] },
        l => { accept_array => 'first', default => false, func => sub { $_[0] = !!$_[0]; 1 } },
        fil => { onerror => undef },
        s => { tableopts => $VNWeb::Chars::List::TABLEOPTS },
    );

    # URL compatibility with old filters
    if(!$opt->{f}->{query} && $opt->{fil}) {
        my $q = eval {
            my $f = filter_parse c => $opt->{fil};
            # Old URLs often had the trait ID as part of the filter, let's remove that.
            $f->{trait_inc} = [ grep "i$_" ne $t->{id}, $f->{trait_inc}->@* ] if $f->{trait_inc};
            delete $f->{trait_inc} if $f->{trait_inc} && !$f->{trait_inc}->@*;
            $f = filter_char_adv $f;
            FU::Validate->compile({ advsearch => 'c' })->validate(@$f > 1 ? $f : undef);
        };
        fu->redirect(perm => fu->path.'?'.query_encode({%$opt, fil => undef, f => $q}));
    }

    $opt->{f} = advsearch_default 'c' if !$opt->{f}{query} && !defined fu->query('f');

    my $where = AND
        'NOT c.hidden',
        $opt->{l} ? 'NOT tc.lie' : (),
        SQL('tc.tid =', $t->{id}),
        SQL('tc.spoil <=', $opt->{m}),
        $opt->{f}->WHERE;

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = fu->SQL('SELECT count(*) FROM chars c JOIN traits_chars tc ON tc.cid = c.id WHERE', $where)->val;
        $list = $count ? fu->SQL('
            SELECT c.id, c.title, c.sex, c.gender, c.image
              FROM', CHARST, 'c
              JOIN traits_chars tc ON tc.cid = c.id
             WHERE', $where, '
             ORDER BY c.sorttitle, c.id
             LIMIT', $opt->{s}->results(), 'OFFSET', $opt->{s}->results()*($opt->{p}-1)
        )->allh : [];
    } || (($count, $list) = (undef, []));

    VNWeb::Chars::List::enrich_listing $list;
    enrich_image_obj image => $list if !$opt->{s}->rows;
    $time = time - $time;

    form_ action => "/$t->{id}", method => 'get', sub {
        article_ sub {
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
            input_ type => 'hidden', name => 'l', value => $opt->{l};
            $opt->{f}->widget_($count, $time);
        };
        VNWeb::Chars::List::listing_ $opt, $list, $count if $count;
    };
}


FU::get qr{/$RE{irev}}, sub($id, $rev=0) {
    my $t = db_entry $id, $rev or fu->notfound;

    framework_ index => !$rev, title => "Trait: $t->{name}", dbobj => $t, hiddenmsg => 1, sub {
        rev_ $t if $rev;
        article_ sub { infobox_ $t; };
        tree_ i => $t->{id};
        chars_ $t if $t->{searchable} && !$t->{hidden};
    };
};

1;
