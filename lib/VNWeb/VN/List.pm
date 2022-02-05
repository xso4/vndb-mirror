package VNWeb::VN::List;

use VNWeb::Prelude;
use VNWeb::AdvSearch;
use VNWeb::Filters;
use VNWeb::Images::Lib;
use VNWeb::ULists::Lib;
use VNWeb::TT::Lib 'tagscore_';

# Returns the tableopts config for this VN list (0) or the VN listing on tags (1).
sub TABLEOPTS {
    my($tags) = @_;
    tableopts _pref => $tags ? 'tableopts_vt' : 'tableopts_v',
        _views => ['rows', 'cards', 'grid'],
        $tags ? (tagscore => {
            name => 'Tag score',
            compat => 'tagscore',
            sort_id => 0,
            sort_sql => 'tvi.rating ?o, v.title',
            sort_default => 'desc'
        }) : (),
        title => {
            name => 'Title',
            compat => 'title',
            sort_id => 1,
            sort_sql => 'v.title',
            sort_default => $tags ? undef : 'asc',
        },
        released => {
            name => 'Release date',
            compat => 'rel',
            sort_id => 2,
            sort_sql => 'v.c_released ?o, v.title',
        },
        length => {
            name => 'Length',
            vis_id => 4,
        },
        developer => {
            name => 'Developer',
            vis_id => 2,
        },
        popularity => {
            name => 'Popularity score',
            compat => 'pop',
            sort_id => 3,
            sort_sql => 'v.c_popularity ?o, v.title',
            vis_id => 0,
            vis_default => 1,
        },
        rating => {
            name => 'Bayesian rating',
            compat => 'rating',
            sort_id => 4,
            sort_sql => 'v.c_rating ?o NULLS LAST, v.title',
            vis_id => 1,
            vis_default => 1,
        },
        average => {
            name => 'Vote average',
            sort_id => 5,
            sort_sql => 'v.c_average ?o NULLS LAST, v.title',
            vis_id => 3,
        },
        votes => {
            name => 'Number of votes',
            sort_id => 6,
            sort_sql => 'v.c_votecount ?o, v.title',
        }
}

my $TABLEOPTS = TABLEOPTS 0;

# Also used by VNWeb::TT::TagPage
sub listing_ {
    my($opt, $list, $count, $tagscore) = @_;

    my sub url { '?'.query_encode %$opt, @_ }

    paginate_ \&url, $opt->{p}, [$count, $opt->{s}->results], 't', sub { $opt->{s}->elm_ };

    my sub len_ {
        my($v) = @_;
        if ($v->{c_lengthnum}) {
            vnlength_ $v->{c_length};
            b_ class => 'grayedout', " ($v->{c_lengthnum})";
        } elsif($_->{length}) {
            txt_ $VN_LENGTH{$v->{length}}{txt};
        }
    }

    div_ class => 'mainbox browse vnbrowse', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc_score', sub { txt_ 'Score'; sortable_ 'tagscore', $opt, \&url } if $tagscore;
                td_ class => 'tc_ulist', '' if auth;
                td_ class => 'tc_title', sub { txt_ 'Title'; sortable_ 'title', $opt, \&url };
                td_ class => 'tc_dev',   'Developer' if $opt->{s}->vis('developer');
                td_ class => 'tc_plat',  '';
                td_ class => 'tc_lang',  '';
                td_ class => 'tc_rel',   sub { txt_ 'Released';   sortable_ 'released',   $opt, \&url };
                td_ class => 'tc_length',sub { txt_ 'Length';                                         } if $opt->{s}->vis('length');
                td_ class => 'tc_pop',   sub { txt_ 'Popularity'; sortable_ 'popularity', $opt, \&url } if $opt->{s}->vis('popularity');
                td_ class => 'tc_rating',sub { txt_ 'Rating';     sortable_ 'rating',     $opt, \&url } if $opt->{s}->vis('rating');
                td_ class => 'tc_average',sub{ txt_ 'Average';    sortable_ 'average',    $opt, \&url } if $opt->{s}->vis('average');
            } };
            tr_ sub {
                td_ class => 'tc_score', sub { tagscore_ $_->{tagscore} } if $tagscore;
                td_ class => 'tc_ulist', sub { ulists_widget_ $_ } if auth;
                td_ class => 'tc_title', sub { a_ href => "/$_->{id}", title => $_->{original}||$_->{title}, $_->{title} };
                td_ class => 'tc_dev',   sub {
                    join_ ' & ', sub {
                        a_ href => "/$_->{id}", title => $_->{original}||$_->{name}, $_->{name};
                    }, sort { $a->{name} cmp $b->{name} || $a->{id} <=> $b->{id} } $_->{developers}->@*;
                } if $opt->{s}->vis('developer');
                td_ class => 'tc_plat',  sub { join_ '', sub { platform_ $_ if $_ ne 'unk' }, sort $_->{platforms}->@* };
                td_ class => 'tc_lang',  sub { join_ '', sub { abbr_ class => "icons lang $_", title => $LANGUAGE{$_}, '' }, reverse sort $_->{lang}->@* };
                td_ class => 'tc_rel',   sub { rdate_ $_->{c_released} };
                td_ class => 'tc_length',sub { len_ $_ } if $opt->{s}->vis('length');
                td_ class => 'tc_pop',   sprintf '%.2f', ($_->{c_popularity}||0)/100 if $opt->{s}->vis('popularity');
                td_ class => 'tc_rating',sub {
                    txt_ sprintf '%.2f', ($_->{c_rating}||0)/100;
                    b_ class => 'grayedout', sprintf ' (%d)', $_->{c_votecount};
                } if $opt->{s}->vis('rating');
                td_ class => 'tc_average',sub {
                    txt_ sprintf '%.2f', ($_->{c_average}||0)/100;
                    b_ class => 'grayedout', sprintf ' (%d)', $_->{c_votecount} if !$opt->{s}->vis('rating');
                } if $opt->{s}->vis('average');
            } for @$list;
        }
    } if $opt->{s}->rows;

    # Contents of the grid & card modes are the same
    my sub infoblock_ {
        my($canlink) = @_; # grid contains an outer <a>, so may not contain links itself.
        my sub lnk_ {
            my($url, $title, $label) = @_;
            a_ href => $url, title => $title, $label if $canlink;
            span_ $label if !$canlink;
        }
        lnk_ "/$_->{id}", $_->{original}||$_->{title}, $_->{title};
        br_;
        join_ '', sub { platform_ $_ if $_ ne 'unk' }, sort $_->{platforms}->@*;
        join_ '', sub { abbr_ class => "icons lang $_", title => $LANGUAGE{$_}, '' }, reverse sort $_->{lang}->@*;
        rdate_ $_->{c_released};
        if($opt->{s}->vis('developer')) {
            br_;
            join_ ' & ', sub {
                lnk_ "/$_->{id}", $_->{original}||$_->{name}, $_->{name};
            }, sort { $a->{name} cmp $b->{name} || $a->{id} <=> $b->{id} } $_->{developers}->@*;
        }
        table_ sub {
            tr_ sub {
                td_ 'Tag score:';
                td_ sub { tagscore_ $_->{tagscore} };
            } if $tagscore;
            tr_ sub {
                td_ 'Length';
                td_ sub { len_ $_ };
            } if $opt->{s}->vis('length');
            tr_ sub {
                td_ 'Popularity:';
                td_ sprintf '%.2f', ($_->{c_popularity}||0)/100;
            } if $opt->{s}->vis('popularity');
            tr_ sub {
                td_ 'Rating:';
                td_ sub {
                    txt_ sprintf '%.2f', ($_->{c_rating}||0)/100;
                    b_ class => 'grayedout', sprintf ' (%d)', $_->{c_votecount};
                };
            } if $opt->{s}->vis('rating');
            tr_ sub {
                td_ 'Average:';
                td_ sub {
                    txt_ sprintf '%.2f', ($_->{c_average}||0)/100;
                    b_ class => 'grayedout', sprintf ' (%d)', $_->{c_votecount} if !$opt->{s}->vis('rating');
                };
            } if $opt->{s}->vis('average');
        }
    }

    div_ class => 'mainbox vncards', sub {
        my($w,$h) = (90,120);
        div_ sub {
            div_ sub {
                if($_->{image}) {
                    my($iw,$ih) = imgsize $_->{image}{width}*100, $_->{image}{height}*100, $w, $h;
                    image_ $_->{image}, width => $iw, height => $ih, url => "/$_->{id}", overlay => undef;
                } else {
                    txt_ 'no image';
                }
            };
            div_ sub {
                ulists_widget_ $_;
                infoblock_ 1;
            };
        } for @$list;
    } if $opt->{s}->cards;

    div_ class => 'mainbox vngrid', sub {
        div_ !$_->{image} || image_hidden($_->{image}) ? (class => 'noimage') : (style => 'background-image: url("'.imgurl($_->{image}{id}).'")'), sub {
            ulists_widget_ $_;
            a_ href => "/$_->{id}", title => $_->{original}||$_->{title}, sub { infoblock_ 0 };
        } for @$list;
    } if $opt->{s}->grid;

    paginate_ \&url, $opt->{p}, [$count, $opt->{s}->results], 'b';
}


# Enrich some extra fields fields needed for listing_()
# Also used by VNWeb::TT::TagPage
sub enrich_listing {
    my $opt = shift;

    enrich developers => id => vid => sub {
        'SELECT v.id AS vid, p.id, p.name, p.original
           FROM vn v, unnest(v.c_developers) vp(id), producers p
          WHERE p.id = vp.id AND v.id IN', $_[0], 'ORDER BY p.name, p.id'
    }, @_ if $opt->{s}->vis('developer');

    enrich_image_obj image => @_ if !$opt->{s}->rows;
    enrich_ulists_widget @_;
}


TUWF::get qr{/v(?:/(?<char>all|[a-z0]))?}, sub {
    my $opt = tuwf->validate(get =>
        q => { onerror => undef },
        sq=> { onerror => undef },
        p => { upage => 1 },
        f => { advsearch_err => 'v' },
        s => { tableopts => $TABLEOPTS },
        ch=> { onerror => [], type => 'array', scalar => 1, values => { onerror => undef, enum => ['0', 'a'..'z'] } },
        fil  => { required => 0 },
        rfil => { required => 0 },
        cfil => { required => 0 },
    )->data;
    $opt->{q} //= $opt->{sq};
    $opt->{ch} = $opt->{ch}[0];

    # compat with old URLs
    my $oldch = tuwf->capture('char');
    $opt->{ch} //= $oldch if defined $oldch && $oldch ne 'all';

    # URL compatibility with old filters
    if(!$opt->{f}->{query} && ($opt->{fil} || $opt->{rfil} || $opt->{cfil})) {
        my $q = eval {
            my $fil  = filter_vn_adv      filter_parse v => $opt->{fil};
            my $rfil = filter_release_adv filter_parse r => $opt->{rfil};
            my $cfil = filter_char_adv    filter_parse c => $opt->{cfil};
            my @q = (
                $fil && @$fil > 1 ? $fil : (),
                $rfil && @$rfil > 1 ? [ 'release', '=', $rfil ] : (),
                $cfil && @$cfil > 1 ? [ 'character', '=', $cfil ] : (),
            );
            tuwf->compile({ advsearch => 'v' })->validate(@q > 1 ? ['and',@q] : @q)->data;
        };
        return tuwf->resRedirect(tuwf->reqPath().'?'.query_encode(%$opt, fil => undef, rfil => undef, cfil => undef, f => $q), 'perm') if $q;
    }

    $opt->{f} = advsearch_default 'v' if !$opt->{f}{query} && !defined tuwf->reqGet('f');

    my $where = sql_and
        'NOT v.hidden', $opt->{f}->sql_where(),
        $opt->{q} ? sql 'v.c_search LIKE ALL (search_query(', \$opt->{q}, '))' : (),
        defined($opt->{ch}) ? sql 'match_firstchar(v.title, ', \$opt->{ch}, ')' : ();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = tuwf->dbVali('SELECT count(*) FROM vn v WHERE', $where);
        $list = $count ? tuwf->dbPagei({results => $opt->{s}->results(), page => $opt->{p}}, '
            SELECT v.id, v.title, v.original, v.c_released, v.c_popularity, v.c_votecount, v.c_rating, v.c_average
                 , v.image, v.c_platforms::text[] AS platforms, v.c_languages::text[] AS lang',
                   $opt->{s}->vis('length') ? ', v.length, v.c_length, v.c_lengthnum' : (), '
              FROM vn v
             WHERE', $where, '
             ORDER BY', $opt->{s}->sql_order(),
        ) : [];
    } || (($count, $list) = (undef, []));

    return tuwf->resRedirect("/$list->[0]{id}") if $count && $count == 1 && $opt->{q} && !defined $opt->{ch};

    enrich_listing($opt, $list);
    $time = time - $time;

    framework_ title => 'Browse visual novels', sub {
        form_ action => '/v', method => 'get', sub {
            div_ class => 'mainbox', sub {
                h1_ 'Browse visual novels';
                searchbox_ v => $opt->{q}//'';
                p_ class => 'browseopts', sub {
                    button_ type => 'submit', name => 'ch', value => ($_//''), ($_//'') eq ($opt->{ch}//'') ? (class => 'optselected') : (), !defined $_ ? 'ALL' : $_ ? uc $_ : '#'
                        for (undef, 'a'..'z', 0);
                };
                input_ type => 'hidden', name => 'ch', value => $opt->{ch}//'';
                $opt->{f}->elm_;
                advsearch_msg_ $count, $time;
            };
            listing_ $opt, $list, $count if $count;
        };
    };
};

1;
