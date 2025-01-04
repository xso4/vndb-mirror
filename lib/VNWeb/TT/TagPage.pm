package VNWeb::TT::TagPage;

use VNWeb::Prelude;
use VNWeb::Filters;
use VNWeb::AdvSearch;
use VNWeb::VN::List;
use VNWeb::VN::Lib;
use VNWeb::TT::Lib 'tree_', 'parents_';


sub rev_ {
    my($t) = @_;
    sub enrich_item {
        enrich_merge parent => 'SELECT id AS parent, name FROM tags WHERE id IN', $_[0]{parents};
        $_[0]{parents} = [ sort { $a->{name} cmp $b->{name} || $a->{parent} <=> $b->{parent} } $_[0]{parents}->@* ];
    }
    enrich_item $t;
    revision_ $t, \&enrich_item,
        [ name         => 'Name'           ],
        [ alias        => 'Aliases'        ],
        [ cat          => 'Category',      fmt => \%TAG_CATEGORY ],
        [ description  => 'Description'    ],
        [ searchable   => 'Searchable',    fmt => 'bool' ],
        [ applicable   => 'Applicable',    fmt => 'bool' ],
        [ defaultspoil => 'Default spoiler level' ],
        [ parents      => 'Parent tags',   fmt => sub { a_ href => "/$_->{parent}", $_->{name}; txt_ ' (primary)' if $_->{main} } ];
}


sub infobox_ {
    my($t) = @_;

    itemmsg_ $t;
    h1_ "Tag: $t->{name}";
    debug_ $t;

    parents_ g => $t;

    div_ class => 'description', sub {
        lit_ bb_format $t->{description};
    } if $t->{description};

    my @prop = (
        $t->{searchable} ? () : 'Not searchable.',
        $t->{applicable} ? () : 'Can not be directly applied to visual novels.'
    );
    p_ class => 'center', sub {
        strong_ 'Properties';
        br_;
        join_ \&br_, sub { txt_ $_ }, @prop;
    } if @prop;

    p_ class => 'center', sub {
        strong_ 'Category';
        br_;
        txt_ $TAG_CATEGORY{$t->{cat}};
    };

    p_ class => 'center', sub {
        strong_ 'Aliases';
        br_;
        join_ \&br_, sub { txt_ $_ }, split /\n/, $t->{alias};
    } if $t->{alias};
}


my $TABLEOPTS = VNWeb::VN::List::TABLEOPTS('tags');


sub vns_ {
    my($t) = @_;

    my $opt = tuwf->validate(get =>
        p => { upage => 1 },
        f => { advsearch_err => 'v' },
        s => { tableopts => $TABLEOPTS },
        m => { onerror => [auth->pref('spoilers')||0], type => 'array', scalar => 1, minlength => 1, values => { enum => [0..2] } },
        l => { onerror => [''], type => 'array', scalar => 1, minlength => 1, values => { anybool => 1 } },
        fil => { onerror => '' },
    )->data;
    $opt->{m} = $opt->{m}[0];
    $opt->{l} = $opt->{l}[0];

    # URL compatibility with old filters
    if(!$opt->{f}->{query} && $opt->{fil}) {
        my $q = eval {
            my $f = filter_parse v => $opt->{fil};
            # Old URLs often had the tag ID as part of the filter, let's remove that.
            $f->{tag_inc} = [ grep "g$_" ne $t->{id}, $f->{tag_inc}->@* ] if $f->{tag_inc};
            delete $f->{tag_inc} if $f->{tag_inc} && !$f->{tag_inc}->@*;
            $f = filter_vn_adv $f;
            tuwf->compile({ advsearch => 'v' })->validate(@$f > 1 ? $f : undef)->data;
        };
        if ($q) {
            tuwf->resRedirect(tuwf->reqPath().'?'.query_encode(%$opt, fil => undef, f => $q), 'perm');
            tuwf->done;
        }
    }

    $opt->{f} = advsearch_default 'v' if !$opt->{f}{query} && !defined tuwf->reqGet('f');

    my $where = sql_and
        'NOT v.hidden',
        $opt->{l} ? 'NOT tvi.lie' : (),
        sql('tvi.tag =', \$t->{id}),
        sql('tvi.spoiler <=', \$opt->{m}),
        $opt->{f}->sql_where();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = tuwf->dbVali('SELECT count(*) FROM vn v JOIN tags_vn_inherit tvi ON tvi.vid = v.id WHERE', $where);
        $list = $count ? tuwf->dbPagei({results => $opt->{s}->results(), page => $opt->{p}}, '
            SELECT tvi.rating AS tagscore, v.id, v.title, v.c_released, v.c_votecount, v.c_rating, v.c_average
                 , ', sql_vnimage, ', v.c_platforms::text[] AS platforms, v.c_languages::text[] AS lang',
                   $opt->{s}->vis('length') ? ', v.length, v.c_length, v.c_lengthnum' : (), '
              FROM', vnt, 'v
              JOIN tags_vn_inherit tvi ON tvi.vid = v.id
             WHERE', $where, '
             ORDER BY', $opt->{s}->sql_order(),
        ) : [];
    } || (($count, $list) = (undef, []));

    VNWeb::VN::List::enrich_listing 1, $opt, $list;
    $time = time - $time;

    form_ action => "/$t->{id}", method => 'get', sub {
        article_ sub {
            p_ class => 'mainopts', sub {
                a_ href => "/g/links?t=$t->{id}", 'Recently tagged';
            };
            h1_ 'Visual novels';
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
            $opt->{f}->elm_($count, $time);
        };
        VNWeb::VN::List::listing_ $opt, $list, $count, 1 if $count;
    };
}


TUWF::get qr{/$RE{grev}}, sub {
    my $t = db_entry tuwf->captures('id', 'rev');
    return tuwf->resNotFound if !$t->{id};

    framework_ index => !tuwf->capture('rev'), title => "Tag: $t->{name}", dbobj => $t, hiddenmsg => 1, sub {
        rev_ $t if tuwf->capture('rev');
        article_ sub { infobox_ $t; };
        tree_ g => $t->{id};
        vns_ $t if $t->{searchable} && !$t->{hidden};
    };
};

1;
