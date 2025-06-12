package VNWeb::VN::List;

use VNWeb::Prelude;
use VNWeb::AdvSearch;
use VNWeb::Filters;
use VNWeb::Images::Lib;
use VNWeb::ULists::Lib;
use VNWeb::VN::Lib;
use VNWeb::TT::Lib 'tagscore_';

# Returns the tableopts config for:
# - this VN list ('vn')
# - this VN list with a search query ('vns')
# - the VN listing on tags ('tags')
# - a user's VN list ('ulist')
# The latter has different numeric identifiers, a sad historical artifact. :(
sub TABLEOPTS($type) {
    my $tags = $type eq 'tags';
    my $vns = $type eq 'vns';
    my $vn = $vns || $type eq 'vn';
    my $ulist = $type eq 'ulist';
    die if !$tags && !$vn && !$ulist;

    # Old popularity column:
    #   sort_id => $ulist ? 14 : 3,
    #   vis_id => $ulist ? 11 : 0,
    tableopts
        _pref => $tags ? 'tableopts_vt' : $vn ? 'tableopts_v' : undef,
        _views => ['rows', 'cards', 'grid'],
        $tags ? (tagscore => {
            name => 'Tag score',
            compat => 'tagscore',
            sort_id => 0,
            sort_sql => 'tvi.rating ?o, v.sorttitle',
            sort_default => 'desc',
            sort_num => 1,
        }) : (),
        $vns ? (qscore => {
            name => 'Relevance',
            sort_id => 0,
            sort_sql => 'sc.score !o, v.sorttitle',
            sort_default => 'asc',
            sort_num => 1,
        }) : (),
        title => {
            name => 'Title',
            compat => 'title',
            sort_id => $ulist ? 0 : 1,
            sort_sql => 'v.sorttitle',
        },
        $ulist ? (
            voted => {
                name => 'Vote date',
                sort_sql => 'uv.vote_date',
                sort_id => 1,
                sort_num => 1,
                vis_id => 0,
                compat => 'voted'
            },
            vote => {
                name => 'Vote',
                sort_sql => 'uv.vote',
                sort_id => 2,
                sort_num => 1,
                vis_id => 1,
                compat => 'vote'
            },
            label => {
                name => 'Labels',
                sort_sql => 'ARRAY(SELECT ul.label FROM unnest(uv.labels) l(id) JOIN ulist_labels ul ON ul.id = l.id WHERE ul.uid = uv.uid AND l.id <> 7)',
                sort_id => 4,
                vis_id => 3,
                compat => 'label'
            },
            added => {
                name => 'Added',
                sort_sql => 'uv.added',
                sort_id => 5,
                sort_num => 1,
                vis_id => 4,
                compat => 'added'
            },
            modified => {
                name => 'Modified',
                sort_sql => 'uv.lastmod',
                sort_id => 6,
                sort_num => 1,
                vis_id => 5,
                compat => 'modified'
            },
            started => {
                name => 'Start date',
                sort_sql => 'uv.started',
                sort_id => 7,
                sort_num => 1,
                vis_id => 6,
                compat => 'started'
            },
            finished => {
                name => 'Finish date',
                sort_sql => 'uv.finished',
                sort_id => 8,
                sort_num => 1,
                vis_id => 7,
                compat => 'finished'
            },
            mylength => {
                name => 'Play time',
                sort_sql => 'ul.sum',
                sort_id => 15,
                sort_num => 1,
                vis_id => 14,
            },
        ) : (),
        released => {
            name => 'Release date',
            compat => 'rel',
            sort_id => $ulist ? 9 : 2,
            sort_sql => 'v.c_released ?o, v.title',
            sort_num => 1,
            vis_id => $ulist ? 8 : undef,
        },
        length => {
            name => 'Length',
            vis_id => $ulist ? 9 : 4,
        },
        developer => {
            name => 'Developer',
            vis_id => $ulist ? 10 : 2,
        },
        rating => {
            name => 'Bayesian rating',
            compat => 'rating',
            sort_id => $ulist ? 11 : 4,
            sort_sql => 'v.c_rat_rank !o NULLS LAST, v.c_votecount ?o, v.sorttitle',
            sort_num => 1,
            vis_id => $ulist ? 12 : 1,
            vis_default => 1,
        },
        average => {
            name => 'Vote average',
            sort_id => $ulist ? 12 : 5,
            sort_sql => 'v.c_average ?o NULLS LAST, v.c_votecount ?o, v.sorttitle',
            sort_num => 1,
            vis_id => $ulist ? 13 : 3,
        },
        votes => {
            name => 'Number of votes',
            sort_id => $ulist ? 13 : 6,
            sort_sql => 'v.c_votecount ?o, v.sorttitle',
            sort_num => 1,
            sort_default => $tags || $vns ? undef : 'desc',
        },
        id => {
            name => $ulist ? 'VN entry added' : 'Date added',
            sort_id => 10,
            sort_sql => 'v.id',
            sort_num => 1,
        };
}

my $TABLEOPTS = TABLEOPTS 'vn';
my $TABLEOPTS_Q = TABLEOPTS 'vns';

sub len_($v) {
    if ($v->{c_lengthnum}) {
        vnlength_ $v->{c_length};
        small_ " ($v->{c_lengthnum})";
    } elsif($v->{length}) {
        txt_ $VN_LENGTH{$v->{length}}{txt};
    }
}

# Also used by VNWeb::TT::TagPage and VNWeb::ULists::List
sub listing_($opt, $list, $count, $tagscore=undef, $labels=undef, $own=undef) {
    my sub url { '?'.query_encode({%$opt, @_}) }

    paginate_ \&url, $opt->{p}, [$count, $opt->{s}->results], 't', $opt->{s};

    my sub votesort {
        txt_ ' (';
        sortable_ 'votes', $opt, \&url, 0;
        txt_ ')'
    }
    article_ class => 'browse vnbrowse', sub {
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
                td_ class => 'tc_rating', sub {
                    txt_ 'Rating'; sortable_ 'rating', $opt, \&url;
                    votesort();
                } if $opt->{s}->vis('rating');
                td_ class => $opt->{s}->vis('rating') ? 'tc_average' : 'tc_rating', sub {
                    txt_ 'Average'; sortable_ 'average', $opt, \&url;
                    votesort() if !$opt->{s}->vis('rating');
                } if $opt->{s}->vis('average');
            } };
            tr_ sub {
                td_ class => 'tc_score', sub { tagscore_ $_->{tagscore} } if $tagscore;
                td_ class => 'tc_ulist', sub { ulists_widget_ $_ } if auth;
                td_ class => 'tc_title', sub { a_ href => "/$_->{id}", tattr $_ };
                td_ class => 'tc_dev',   sub {
                    join_ ' & ', sub {
                        a_ href => "/$_->{id}", tattr $_;
                    }, $_->{developers}->@*;
                } if $opt->{s}->vis('developer');
                td_ class => 'tc_plat',  sub { join_ '', sub { platform_ $_ if $_ ne 'unk' }, sort $_->{platforms}->@* };
                td_ class => 'tc_lang',  sub { join_ '', sub { abbr_ class => "icon-lang-$_", title => $LANGUAGE{$_}{txt}, '' }, reverse sort $_->{lang}->@* };
                td_ class => 'tc_rel',   sub { rdate_ $_->{c_released} };
                td_ class => 'tc_length',sub { len_ $_ } if $opt->{s}->vis('length');
                td_ class => 'tc_rating',sub {
                    txt_ $_->{c_rating} ? sprintf '%.2f', $_->{c_rating}/100 : '-';
                    small_ sprintf ' (%d)', $_->{c_votecount};
                } if $opt->{s}->vis('rating');
                td_ class => 'tc_average',sub {
                    txt_ $_->{c_average} ? sprintf '%.2f', $_->{c_average}/100 : '-';
                    small_ sprintf ' (%d)', $_->{c_votecount} if !$opt->{s}->vis('rating');
                } if $opt->{s}->vis('average');
            } for @$list;
        }
    } if $opt->{s}->rows;

    # Contents of the grid & card modes are the same
    my sub infoblock_ {
        my($canlink) = @_; # grid contains an outer <a>, so may not contain links itself.
        my sub lnk_ {
            my($url, @attr) = @_;
            a_ href => $url, @attr if $canlink;
            span_ @attr if !$canlink;
        }
        lnk_ "/$_->{id}", tattr $_;
        if(!$labels || $opt->{s}->vis('released')) {
            br_;
            join_ '', sub { platform_ $_ if $_ ne 'unk' }, sort $_->{platforms}->@*;
            join_ '', sub { abbr_ class => "icon-lang-$_", title => $LANGUAGE{$_}{txt}, '' }, reverse sort $_->{lang}->@*;
            rdate_ $_->{c_released};
        }
        if($opt->{s}->vis('developer')) {
            br_;
            join_ ' & ', sub {
                lnk_ "/$_->{id}", tattr $_;
            }, $_->{developers}->@*;
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
                td_ $opt->{s}->vis('vote') ? 'Vote:' : 'Voted:';
                td_ sub {
                    txt_ fmtvote $_->{vote} if $opt->{s}->vis('vote');
                    txt_ ' on '.($_->{vote_date} ? fmtdate $_->{vote_date}, 'compact' : '-') if $opt->{s}->vis('voted');
                }
            } if $opt->{s}->vis('vote') || $opt->{s}->vis('voted');
            tr_ sub {
                td_ 'Labels:';
                td_ sub {
                    my %labels = map +($_,1), $_->{labels}->@*;
                    my @l = grep $labels{$_->{id}} && $_->{id} != 7, @$labels;
                    txt_ @l ? join ', ', map $_->{label}, @l : '-';
                };
            } if $opt->{s}->vis('label');
            tr_ sub {
                td_ 'Added on:';
                td_ fmtdate $_->{added}, 'compact';
            } if $opt->{s}->vis('added');
            tr_ sub {
                td_ 'Modified on:';
                td_ fmtdate $_->{lastmod}, 'compact';
            } if $opt->{s}->vis('modified');
            tr_ sub {
                td_ 'Started:';
                td_ id => $own ? "ulist_started_$_->{id}" : undef, $_->{started}||'-';
            } if $opt->{s}->vis('started');
            tr_ sub {
                td_ 'Finished:';
                td_ id => $own ? "ulist_finished_$_->{id}" : undef, $_->{finished}||'-';
            } if $opt->{s}->vis('finished');
            tr_ sub {
                td_ 'Play time:';
                td_ sub {
                    my $l = sub { !$_->{mylength_count} ? txt_ '-' : vnlength_ $_->{mylength_sum}, $_->{mylength_count} };
                    $own ? a_ href => "/$_->{id}/lengthvote", $l : $l->();
                };
            } if $opt->{s}->vis('mylength');
            tr_ sub {
                td_ 'Rating:';
                td_ sub {
                    txt_ $_->{c_rating} ? sprintf '%.2f', $_->{c_rating}/100 : '-';
                    small_ sprintf ' (%d)', $_->{c_votecount};
                };
            } if $opt->{s}->vis('rating');
            tr_ sub {
                td_ 'Average:';
                td_ sub {
                    txt_ $_->{c_average} ? sprintf '%.2f', $_->{c_average}/100 : '';
                    small_ sprintf ' (%d)', $_->{c_votecount} if !$opt->{s}->vis('rating');
                };
            } if $opt->{s}->vis('average');
        }
    }

    article_ class => 'vncards', sub {
        my($w,$h) = (90,120);
        div_ id => $own ? "ulist_vid_$_->{id}" : undef, sub {
            div_ sub {
                if($_->{vnimage}) {
                    my($iw,$ih) = imgsize $_->{vnimage}{width}*100, $_->{vnimage}{height}*100, $w, $h;
                    image_ $_->{vnimage}, width => $iw, height => $ih, url => "/$_->{id}", overlay => 0;
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

    article_ class => 'vngrid', sub {
        # TODO: landscape images are badly upscaled, should probably generate more suitable thumbnails for this view.
        div_ id => $own ? "ulist_vid_$_->{id}" : undef,
                !$_->{vnimage} || image_hidden($_->{vnimage}) ? (class => 'noimage') : (style => 'background-image: url("'.thumburl($_->{vnimage}).'")'), sub {
            ulists_widget_ $_;
            a_ href => "/$_->{id}", title => $_->{title}[3], sub { infoblock_ 0 };
        } for @$list;
    } if $opt->{s}->grid;

    paginate_ \&url, $opt->{p}, [$count, $opt->{s}->results], 'b';
}


# Enrich some extra fields fields needed for listing_()
# Also used by TT::TagPage and UList::List
sub enrich_listing($widget, $opt, $lst) {
    fu->enrich(aoh => 'developers', sub { SQL
        'SELECT v.id, p.id, p.title
           FROM vn v, unnest(v.c_developers) vp(id),', PRODUCERST, 'p
          WHERE p.id = vp.id AND v.id', IN $_, 'ORDER BY p.sorttitle, p.id'
    }, $lst) if $opt->{s}->vis('developer');

    enrich_vnimage $lst if !$opt->{s}->rows;
    enrich_ulists_widget $lst if $widget;
}


FU::get qr{/v(?:/(all|[a-z0]))?}, sub($char=undef) {
    my $opt = fu->query(
        q => { searchquery => 1 },
        sq=> { searchquery => 1 },
        p => { upage => 1 },
        f => { advsearch_err => 'v' },
        ch=> { accept_array => 'first', onerror => undef, enum => ['0', 'a'..'z'] },
        fil  => { onerror => undef },
        rfil => { onerror => undef },
        cfil => { onerror => undef },
    );
    $opt->{q} = $opt->{sq} if !$opt->{q};
    $opt->{s} = fu->query(s => { tableopts => $opt->{q} ? $TABLEOPTS_Q : $TABLEOPTS });
    $opt->{s} = $opt->{s}->sort_param(qscore => 'a') if $opt->{q} && fu->query('sb');

    # compat with old URLs
    $opt->{ch} //= $char if defined $char && $char ne 'all';

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
            FU::Validate->compile({ advsearch => 'v' })->validate(@q > 1 ? ['and',@q] : @q);
        };
        fu->redirect(perm => fu->path.'?'.query_encode({%$opt, fil => undef, rfil => undef, cfil => undef, f => $q})) if $q;
    }

    $opt->{f} = advsearch_default 'v' if !$opt->{f}{query} && !defined fu->query('f');

    my $where = AND
        'NOT v.hidden',
        $opt->{f}->WHERE(),
        defined $opt->{ch} ? SQL 'match_firstchar(v.sorttitle, ', $opt->{ch}, ')' : ();

    my $time = time;
    my($count, $list);
    db_maytimeout {
        $count = fu->SQL('SELECT count(*) FROM', VNT, 'v WHERE', AND $where, $opt->{q}->WHERE('v', 'v.id'))->val;
        $list = $count ? fu->SQL('
            SELECT v.id, v.title, v.c_released, v.c_votecount, v.c_rating, v.c_average
                 , ', VNIMAGE, ', v.c_platforms AS platforms, v.c_languages AS lang',
                   $opt->{s}->vis('length') ? ', v.length, v.c_length, v.c_lengthnum' : (), '
              FROM', VNT, 'v', $opt->{q}->JOIN('v', 'v.id'), '
             WHERE', $where, '
             ORDER BY', $opt->{s}->ORDER, '
             LIMIT', $opt->{s}->results(), 'OFFSET', $opt->{s}->results()*($opt->{p}-1),
        )->allh : [];
    } || (($count, $list) = (undef, []));

    my $fullq = join '', $opt->{q}->words->@*;
    my $other = length $fullq && $opt->{s}->sorted('qscore') && $opt->{p} == 1 ? fu->SQL("
        SELECT x.id, i.title
          FROM (
            SELECT DISTINCT id
              FROM search_cache
             WHERE NOT (id BETWEEN 'v1' AND vndbid_max('v'))
               AND NOT (id BETWEEN 'r1' AND vndbid_max('r'))
               AND label =", $fullq, ') x,
              ', ITEM_INFO('id', 'null'), 'i
         WHERE NOT i.hidden
         ORDER BY vndbid_type(x.id) DESC, i.title[2]
    ')->allh : [];

    fu->redirect(temp => "/$list->[0]{id}") if $count && $count == 1 && $opt->{p} == 1 && $opt->{q} && !defined $opt->{ch} && !@$other;

    enrich_listing(1, $opt, $list);
    $time = time - $time;

    framework_ title => 'Browse visual novels', sub {
        form_ action => '/v', method => 'get', sub {
            article_ sub {
                h1_ 'Browse visual novels';
                searchbox_ v => $opt->{q};
                p_ class => 'browseopts', sub {
                    button_ type => 'submit', name => 'ch', value => ($_//''), ($_//'') eq ($opt->{ch}//'') ? (class => 'optselected') : (), !defined $_ ? 'ALL' : $_ ? uc $_ : '#'
                        for (undef, 'a'..'z', 0);
                };
                input_ type => 'hidden', name => 'ch', value => $opt->{ch}//'';
                $opt->{f}->widget_($count, $time);
            };
            article_ sub {
                h1_ 'Did you mean to search for...';
                ul_ style => 'column-width: 250px', sub {
                    li_ sub {
                        strong_ {qw/r Release p Producer c Character s Staff g Tag i Trait/}->{substr $_->{id}, 0, 1};
                        txt_ ': ';
                        a_ href => "/$_->{id}", tattr $_;
                    } for @$other;
                };
            } if @$other;
            listing_ $opt, $list, $count if $count;
        };
    };
};

1;
