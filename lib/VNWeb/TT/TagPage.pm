package VNWeb::TT::TagPage;

use VNWeb::Prelude;
use VNWeb::Filters;
use VNWeb::AdvSearch;
use VNWeb::VN::List;
use VNWeb::TT::Lib 'tree_';


sub parents_ {
    my($t) = @_;

    my %t;
    push $t{$_->{child}}->@*, $_ for tuwf->dbAlli('
        WITH RECURSIVE p(id,child,name) AS (
            SELECT ', \$t->{id}, '::int, 0, NULL::text
            UNION
            SELECT t.id, p.id, t.name FROM p JOIN tags_parents tp ON tp.tag = p.id JOIN tags t ON t.id = tp.parent
        ) SELECT * FROM p WHERE child <> 0 ORDER BY name
    ')->@*;

    my sub rec {
        $t{$_[0]} ? map { my $e=$_; map [ @$_, $e ], __SUB__->($e->{id}) } $t{$_[0]}->@* : []
    }

    p_ sub {
        join_ \&br_, sub {
            a_ href => '/g', 'Tags';
            for (@$_) {
                txt_ ' > ';
                a_ href => "/g$_->{id}", $_->{name};
            }
            txt_ ' > ';
            txt_ $t->{name};
        }, rec($t->{id});
    };
}


sub infobox_ {
    my($t) = @_;

    p_ class => 'mainopts', sub {
        a_ href => "/g$t->{id}/add", 'Create child tag';
    } if $t->{state} != 1 && can_edit g => {};
    h1_ "Tag: $t->{name}";
    debug_ $t;

    div_ class => 'warning', sub {
        h2_ 'Tag deleted';
        p_ sub {
            txt_ 'This tag has been removed from the database, and cannot be used or re-added.';
            br_;
            txt_ 'File a request on the ';
            a_ href => '/t/db', 'discussion board';
            txt_ ' if you disagree with this.';
        }
    } if $t->{state} == 1;

    div_ class => 'notice', sub {
        h2_ 'Waiting for approval';
        p_ 'This tag is waiting for a moderator to approve it. You can still use it to tag VNs as you would with a normal tag.';
    } if $t->{state} == 0;

    parents_ $t;

    p_ class => 'description', sub {
        lit_ bb_format $t->{description};
    } if $t->{description};

    my @prop = (
        $t->{searchable} ? () : 'Not searchable.',
        $t->{applicable} ? () : 'Can not be directly applied to visual novels.'
    );
    p_ class => 'center', sub {
        b_ 'Properties';
        br_;
        join_ \&br_, sub { txt_ $_ }, @prop;
    } if @prop;

    p_ class => 'center', sub {
        b_ 'Category';
        br_;
        txt_ $TAG_CATEGORY{$t->{cat}};
    };

    p_ class => 'center', sub {
        b_ 'Aliases';
        br_;
        join_ \&br_, sub { txt_ $_ }, $t->{aliases}->@*;
    } if $t->{aliases}->@*;
}


sub vns_ {
    my($t) = @_;

    my $opt = tuwf->validate(get =>
        p => { upage => 1 },
        f => { advsearch_err => 'v' },
        s => { onerror => 'tagscore', enum => [qw/tagscore title rel pop rating/] },
        o => { onerror => 'd', enum => ['a','d'] },
        m => { onerror => [auth->pref('spoilers')||0], type => 'array', scalar => 1, minlength => 1, values => { enum => [0..2] } },
        fil => { required => 0 },
    )->data;
    $opt->{m} = $opt->{m}[0];

    # URL compatibility with old filters
    if(!$opt->{f}->{query} && $opt->{fil}) {
        my $q = eval {
            my $f = filter_parse v => $opt->{fil};
            # Old URLs often had the tag ID as part of the filter, let's remove that.
            $f->{tag_inc} = [ grep $_ != $t->{id}, $f->{tag_inc}->@* ] if $f->{tag_inc};
            delete $f->{tag_inc} if $f->{tag_inc} && !$f->{tag_inc}->@*;
            $f = filter_vn_adv $f;
            tuwf->compile({ advsearch => 'v' })->validate(@$f > 1 ? $f : undef)->data;
        };
        if(!$q) {
            warn "Filter compatibility conversion failed\n$@";
        } elsif($q->{query}) {
            return tuwf->resRedirect(tuwf->reqPath().'?'.query_encode(%$opt, fil => undef, f => $q), 'temp');
        }
    }

    $opt->{f} = advsearch_default 'v' if !$opt->{f}{query} && !defined tuwf->reqGet('f');

    my $where = sql 'tvi.tag =', \$t->{id}, 'AND NOT v.hidden AND tvi.spoiler <=', \$opt->{m}, 'AND', $opt->{f}->sql_where();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = tuwf->dbVali('SELECT count(*) FROM vn v JOIN tags_vn_inherit tvi ON tvi.vid = v.id WHERE', $where);
        $list = $count ? tuwf->dbPagei({results => 50, page => $opt->{p}}, '
            SELECT tvi.rating AS tagscore, v.id, v.title, v.original, v.c_released, v.c_popularity, v.c_votecount, v.c_rating
                 , v.c_platforms::text[] AS platforms, v.c_languages::text[] AS lang
              FROM vn v
              JOIN tags_vn_inherit tvi ON tvi.vid = v.id
             WHERE', $where, '
             ORDER BY', sprintf {
                 tagscore => 'tvi.rating %s, v.title',
                 title    => 'v.title %s',
                 rel      => 'v.c_released %s, v.title',
                 pop      => 'v.c_popularity %s NULLS LAST, v.title',
                 rating   => 'v.c_rating %s NULLS LAST, v.title'
             }->{$opt->{s}}, $opt->{o} eq 'a' ? 'ASC' : 'DESC'
        ) : [];
    } || (($count, $list) = (undef, []));

    VNWeb::VN::List::enrich_userlist $list;
    $time = time - $time;

    div_ class => 'mainbox', sub {
        p_ class => 'mainopts', sub {
            a_ href => "/g/links?t=$t->{id}", 'Recently tagged';
        };
        h1_ 'Visual novels';
        form_ action => "/g$t->{id}", method => 'get', sub {
            p_ class => 'browseopts', sub {
                button_ type => 'submit', name => 'm', value => 0, $opt->{m} == 0 ? (class => 'optselected') : (), 'Hide spoilers';
                button_ type => 'submit', name => 'm', value => 1, $opt->{m} == 1 ? (class => 'optselected') : (), 'Show minor spoilers';
                button_ type => 'submit', name => 'm', value => 2, $opt->{m} == 2 ? (class => 'optselected') : (), 'Spoil me!';
            };
            input_ type => 'hidden', name => 'o', value => $opt->{o};
            input_ type => 'hidden', name => 's', value => $opt->{s};
            input_ type => 'hidden', name => 'm', value => $opt->{m};
            $opt->{f}->elm_;
            advsearch_msg_ $count, $time;
        };
    };
    VNWeb::VN::List::listing_ $opt, $list, $count, 1 if $count;
}


TUWF::get qr{/$RE{gid}}, sub {
    my $t = tuwf->dbRowi('SELECT id, name, description, state, c_items, cat, defaultspoil, searchable, applicable FROM tags WHERE id =', \tuwf->capture('id'));
    return tuwf->resNotFound if !$t->{id};

    enrich_flatten aliases => id => tag => sub { 'SELECT tag, alias FROM tags_aliases WHERE tag IN', $_, 'ORDER BY alias' }, $t;

    framework_ index => $t->{state} == 2, title => "Tag: $t->{name}", type => 'g', dbobj => $t, sub {
        div_ class => 'mainbox', sub { infobox_ $t; };
        tree_ g => $t->{id};
        vns_ $t if $t->{searchable} && $t->{state} == 2;
    };
};

1;
