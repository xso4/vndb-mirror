package VNWeb::TT::TraitPage;

use VNWeb::Prelude;
use VNWeb::Filters;
use VNWeb::AdvSearch;
use VNWeb::TT::Lib 'tree_', 'parents_';


sub infobox_ {
    my($t) = @_;

    p_ class => 'mainopts', sub {
        a_ href => "/i$t->{id}/add", 'Create child trait';
    } if $t->{state} != 1 && can_edit i => {};
    h1_ "Trait: $t->{name}";
    debug_ $t;

    div_ class => 'warning', sub {
        h2_ 'Trait deleted';
        p_ sub {
            txt_ 'This trait has been removed from the database, and cannot be used or re-added.';
            br_;
            txt_ 'File a request on the ';
            a_ href => '/t/db', 'discussion board';
            txt_ ' if you disagree with this.';
        }
    } if $t->{state} == 1;

    div_ class => 'notice', sub {
        h2_ 'Waiting for approval';
        p_ 'This trait is waiting for a moderator to approve it.';
    } if $t->{state} == 0;

    parents_ i => $t;

    p_ class => 'description', sub {
        lit_ bb_format $t->{description};
    } if $t->{description};

    my @prop = (
        !$t->{sexual}    ? () : 'Indicates sexual content.',
        $t->{searchable} ? () : 'Not searchable.',
        $t->{applicable} ? () : 'Can not be directly applied to characters.',
    );
    p_ class => 'center', sub {
        b_ 'Properties';
        br_;
        join_ \&br_, sub { txt_ $_ }, @prop;
    } if @prop;

    p_ class => 'center', sub {
        b_ 'Aliases';
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
        fil => { required => 0 },
    )->data;
    $opt->{m} = $opt->{m}[0];

    # URL compatibility with old filters
    if(!$opt->{f}->{query} && $opt->{fil}) {
        my $q = eval {
            my $f = filter_parse c => $opt->{fil};
            # Old URLs often had the trait ID as part of the filter, let's remove that.
            $f->{trait_inc} = [ grep $_ != $t->{id}, $f->{trait_inc}->@* ] if $f->{trait_inc};
            delete $f->{trait_inc} if $f->{trait_inc} && !$f->{trait_inc}->@*;
            $f = filter_char_adv $f;
            tuwf->compile({ advsearch => 'c' })->validate(@$f > 1 ? $f : undef)->data;
        };
        return tuwf->resRedirect(tuwf->reqPath().'?'.query_encode(%$opt, fil => undef, f => $q), 'perm') if $q;
    }

    $opt->{f} = advsearch_default 'c' if !$opt->{f}{query} && !defined tuwf->reqGet('f');

    my $where = sql 'tc.tid =', \$t->{id}, 'AND NOT c.hidden AND tc.spoil <=', \$opt->{m}, 'AND', $opt->{f}->sql_where();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = tuwf->dbVali('SELECT count(*) FROM chars c JOIN traits_chars tc ON tc.cid = c.id WHERE', $where);
        $list = $count ? tuwf->dbPagei({results => 50, page => $opt->{p}}, '
            SELECT c.id, c.name, c.original, c.gender
              FROM chars c
              JOIN traits_chars tc ON tc.cid = c.id
             WHERE', $where, '
             ORDER BY c.name, c.id'
        ) : [];
    } || (($count, $list) = (undef, []));

    VNWeb::Chars::List::enrich_listing $list;
    $time = time - $time;

    div_ class => 'mainbox', sub {
        h1_ 'Characters';
        form_ action => "/i$t->{id}", method => 'get', sub {
            p_ class => 'browseopts', sub {
                button_ type => 'submit', name => 'm', value => 0, $opt->{m} == 0 ? (class => 'optselected') : (), 'Hide spoilers';
                button_ type => 'submit', name => 'm', value => 1, $opt->{m} == 1 ? (class => 'optselected') : (), 'Show minor spoilers';
                button_ type => 'submit', name => 'm', value => 2, $opt->{m} == 2 ? (class => 'optselected') : (), 'Spoil me!';
            };
            input_ type => 'hidden', name => 'm', value => $opt->{m};
            $opt->{f}->elm_;
            advsearch_msg_ $count, $time;
        };
    };
    VNWeb::Chars::List::listing_ $opt, $list, $count, 1 if $count;
}


TUWF::get qr{/$RE{iid}}, sub {
    my $t = tuwf->dbRowi('SELECT id, name, alias, description, state, c_items, sexual, searchable, applicable FROM traits WHERE id =', \tuwf->capture('id'));
    return tuwf->resNotFound if !$t->{id};

    framework_ index => $t->{state} == 2, title => "Trait: $t->{name}", type => 'i', dbobj => $t, sub {
        div_ class => 'mainbox', sub { infobox_ $t; };
        tree_ i => $t->{id};
        chars_ $t if $t->{searchable} && $t->{state} == 2;
    };
};

1;
