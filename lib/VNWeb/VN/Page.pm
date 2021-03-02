package VNWeb::VN::Page;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;
use VNWeb::Images::Lib qw/image_flagging_display image_ enrich_image_obj/;
use VNDB::Func 'fmtrating';


# Enrich everything necessary to at least render infobox_() and tabs_().
# Also used by Chars::VNTab & Reviews::VNTab
sub enrich_vn {
    my($v, $revonly) = @_;
    enrich_merge id => 'SELECT id, c_votecount FROM vn WHERE id IN', $v;
    enrich_merge vid => 'SELECT id AS vid, title, original FROM vn WHERE id IN', $v->{relations};
    enrich_merge aid => 'SELECT id AS aid, title_romaji, title_kanji, year, type, ann_id, lastfetch FROM anime WHERE id IN', $v->{anime};
    enrich_extlinks v => $v;
    enrich_image_obj image => $v;
    enrich_image_obj scr => $v->{screenshots};

    # The queries below are not relevant for revisions
    return if $revonly;

    # This fetches rather more information than necessary for infobox_(), but it'll have to do.
    # (And we'll need it for the releases tab anyway)
    $v->{releases} = tuwf->dbAlli('
        SELECT r.id, r.type, r.patch, r.released, r.gtin,', sql_extlinks(r => 'r.'), '
             , (SELECT COUNT(*) FROM releases_vn rv WHERE rv.id = r.id) AS num_vns
          FROM releases r
          JOIN releases_vn rv ON rv.id = r.id
         WHERE NOT r.hidden AND rv.vid =', \$v->{id}
    );
    enrich_extlinks r => $v->{releases};

    $v->{reviews} = tuwf->dbRowi('SELECT COUNT(*) FILTER(WHERE isfull) AS full, COUNT(*) FILTER(WHERE NOT isfull) AS mini, COUNT(*) AS total FROM reviews WHERE NOT c_flagged AND vid =', \$v->{id});

    my $rating = 'avg(CASE WHEN tv.ignore OR (u.id IS NOT NULL AND NOT u.perm_tag) THEN NULL ELSE tv.vote END)';
    $v->{tags} = tuwf->dbAlli("
        SELECT t.id, t.name, t.cat, $rating as rating
             , coalesce(avg(CASE WHEN tv.ignore OR (u.id IS NOT NULL AND NOT u.perm_tag) THEN NULL ELSE tv.spoiler END), t.defaultspoil) as spoiler
          FROM tags t
          JOIN tags_vn tv ON tv.tag = t.id
          LEFT JOIN users u ON u.id = tv.uid
         WHERE t.state = 1+1 AND tv.vid =", \$v->{id}, "
         GROUP BY t.id, t.name, t.cat
        HAVING $rating > 0
         ORDER BY rating DESC"
    );
}


# Enrich everything necessary for rev_() (includes enrich_vn())
sub enrich_item {
    my($v, $full) = @_;
    enrich_vn $v, !$full;
    enrich_merge aid => 'SELECT id AS sid, aid, name, original FROM staff_alias WHERE aid IN', $v->{staff}, $v->{seiyuu};
    enrich_merge cid => 'SELECT id AS cid, name AS char_name, original AS char_original FROM chars WHERE id IN', $v->{seiyuu};

    $v->{relations}   = [ sort { idcmp($a->{vid}, $b->{vid}) } $v->{relations}->@* ];
    $v->{anime}       = [ sort { $a->{aid} <=> $b->{aid} } $v->{anime}->@* ];
    $v->{staff}       = [ sort { $a->{aid} <=> $b->{aid} || $a->{role} cmp $b->{role} } $v->{staff}->@* ];
    $v->{seiyuu}      = [ sort { $a->{aid} <=> $b->{aid} || idcmp($a->{cid}, $b->{cid}) || $a->{note} cmp $b->{note} } $v->{seiyuu}->@* ];
    $v->{screenshots} = [ sort { idcmp($a->{scr}{id}, $b->{scr}{id}) } $v->{screenshots}->@* ];
}


sub og {
    my($v) = @_;
    +{
        description => bb_format($v->{desc}, text => 1),
        image => $v->{image} && !$v->{image}{sexual} && !$v->{image}{violence} ? imgurl($v->{image}{id}) :
                 [map $_->{scr}{sexual}||$_->{scr}{violence}?():(imgurl($_->{scr}{id})), $v->{screenshots}->@*]->[0]
    }
}


# The voting and review options are hidden if nothing has been released yet.
sub canvote {
    my($v) = @_;
    my $minreleased = min grep $_, map $_->{released}, $v->{releases}->@*;
    $minreleased && $minreleased <= strftime('%Y%m%d', gmtime)
}


sub rev_ {
    my($v) = @_;
    revision_ $v, \&enrich_item,
        [ title       => 'Title (romaji)' ],
        [ original    => 'Original title' ],
        [ alias       => 'Alias'          ],
        [ olang       => 'Original language', fmt => \%LANGUAGE ],
        [ desc        => 'Description'    ],
        [ length      => 'Length',        fmt => \%VN_LENGTH ],
        [ staff       => 'Credits',       fmt => sub {
            a_ href => "/$_->{sid}", title => $_->{original}||$_->{name}, $_->{name} if $_->{sid};
            b_ class => 'grayedout', '[removed alias]' if !$_->{sid};
            txt_ " [$CREDIT_TYPE{$_->{role}}]";
            txt_ " [$_->{note}]" if $_->{note};
        }],
        [ seiyuu      => 'Seiyuu',        fmt => sub {
            a_ href => "/$_->{sid}", title => $_->{original}||$_->{name}, $_->{name} if $_->{sid};
            b_ class => 'grayedout', '[removed alias]' if !$_->{sid};
            txt_ ' as ';
            a_ href => "/$_->{cid}", title => $_->{char_original}||$_->{char_name}, $_->{char_name};
            txt_ " [$_->{note}]" if $_->{note};
        }],
        [ relations   => 'Relations',     fmt => sub {
            txt_ sprintf '[%s] %s: ', $_->{official} ? 'official' : 'unofficial', $VN_RELATION{$_->{relation}}{txt};
            a_ href => "/$_->{vid}", title => $_->{original}||$_->{title}, $_->{title};
        }],
        [ anime       => 'Anime',         fmt => sub { a_ href => "https://anidb.net/anime/$_->{aid}", "a$_->{aid}" }],
        [ screenshots => 'Screenshots',   fmt => sub {
            txt_ '[';
            a_ href => "/$_->{rid}", $_->{rid} if $_->{rid};
            txt_ 'no release' if !$_->{rid};
            txt_ '] ';
            a_ href => imgurl($_->{scr}{id}), 'data-iv' => "$_->{scr}{width}x$_->{scr}{height}::$_->{scr}{sexual}$_->{scr}{violence}$_->{scr}{votecount}", $_->{scr}{id};
            txt_ ' [';
            a_ href => "/img/$_->{scr}{id}", image_flagging_display $_->{scr};
            txt_ '] ';
            # The old NSFW flag has been removed around 2020-07-14, so not relevant for edits made later on.
            b_ class => 'grayedout', sprintf 'old flag: %s', $_->{nsfw} ? 'NSFW' : 'Safe' if $_[0]{rev_added} < 1594684800;
        }],
        [ image       => 'Image',         fmt => sub { image_ $_ } ],
        [ img_nsfw    => 'Image NSFW (unused)', fmt => sub { txt_ $_ ? 'Not safe' : 'Safe' } ],
        revision_extlinks 'v'
}


sub infobox_relations_ {
    my($v) = @_;
    return if !$v->{relations}->@*;

    my %rel;
    push $rel{$_->{relation}}->@*, $_ for sort { $a->{title} cmp $b->{title} } $v->{relations}->@*;

    tr_ sub {
        td_ 'Relations';
        td_ class => 'relations', sub { dl_ sub {
            for(sort keys %rel) {
                dt_ $VN_RELATION{$_}{txt};
                dd_ sub {
                    join_ \&br_, sub {
                        b_ class => 'grayedout', '[unofficial] ' if !$_->{official};
                        a_ href => "/$_->{vid}", title => $_->{original}||$_->{title}, shorten $_->{title}, 40;
                    }, $rel{$_}->@*;
                }
            }
        }}
    }
}


sub infobox_producers_ {
    my($v) = @_;

    my $p = tuwf->dbAlli('
        SELECT p.id, p.name, p.original, rl.lang, bool_or(rp.developer) as developer, bool_or(rp.publisher) as publisher, min(r.type) as type, bool_or(r.official) as official
          FROM releases_vn rv
          JOIN releases r ON r.id = rv.id
          JOIN releases_lang rl ON rl.id = rv.id
          JOIN releases_producers rp ON rp.id = rv.id
          JOIN producers p ON p.id = rp.pid
         WHERE NOT r.hidden AND rv.vid =', \$v->{id}, '
         GROUP BY p.id, p.name, p.original, rl.lang
         ORDER BY NOT bool_or(r.official), MIN(r.released), p.name
    ');
    return if !@$p;

    my $hasfull = grep $_->{type} eq 'complete', @$p;
    my %dev;
    my @dev = grep $_->{developer} && (!$hasfull || $_->{type} ne 'trial') && !$dev{$_->{id}}++, @$p;

    tr_ sub {
        td_ 'Developer';
        td_ sub {
            join_ ' & ', sub { a_ href => "/$_->{id}", title => $_->{original}||$_->{name}, $_->{name}; }, @dev;
        };
    } if @dev;

    my(%lang, @lang, $lang);
    for(grep $_->{publisher} && (!$hasfull || $_->{type} ne 'trial'), @$p) {
        push @lang, $_->{lang} if !$lang{$_->{lang}};
        push $lang{$_->{lang}}->@*, $_;
    }

    tr_ sub {
        td_ 'Publishers';
        td_ sub {
            use sort 'stable';
            join_ \&br_, sub {
                abbr_ class => "icons lang $_", title => $LANGUAGE{$_}, '';
                join_ ' & ', sub { a_ href => "/$_->{id}", $_->{official} ? () : (class => 'grayedout'), title => $_->{original}||$_->{name}, $_->{name} }, $lang{$_}->@*;
            }, sort { ($b eq $v->{olang}) cmp ($a eq $v->{olang}) } @lang;
        }
    } if keys %lang;
}


sub infobox_affiliates_ {
    my($v) = @_;

    # If the same shop link has been added to multiple releases, use the 'first' matching type in this list.
    my @type = ('bundle', '', 'partial', 'trial', 'patch');

    # url => [$title, $url, $price, $type]
    my %links;
    for my $rel ($v->{releases}->@*) {
        my $type =    $rel->{patch} ? 4 :
            $rel->{type} eq 'trial' ? 3 :
          $rel->{type} eq 'partial' ? 2 :
                $rel->{num_vns} > 1 ? 0 : 1;

        $links{$_->[1]} = [ @$_, min $type, $links{$_->[1]}[3]||9 ] for grep $_->[2], $rel->{extlinks}->@*;
    }
    return if !keys %links;

    tr_ id => 'buynow', sub {
        td_ 'Shops';
        td_ sub {
            join_ \&br_, sub {
                b_ class => 'standout', '» ';
                a_ href => $_->[1], sub {
                    txt_ $_->[2];
                    b_ class => 'grayedout', ' @ ';
                    txt_ $_->[0];
                    b_ class => 'grayedout', " ($type[$_->[3]])" if $_->[3] != 1;
                };
            }, sort { $a->[0] cmp $b->[0] || $a->[2] cmp $b->[2] } values %links;
        }
    }
}


sub infobox_anime_ {
    my($v) = @_;
    return if !$v->{anime}->@*;
    tr_ sub {
        td_ 'Related anime';
        td_ class => 'anime', sub { join_ \&br_, sub {
            if(!$_->{lastfetch} || !$_->{year} || !$_->{title_romaji}) {
                b_ sub {
                    txt_ '[no information available at this time: ';
                    a_ href => 'https://anidb.net/anime/'.$_->{aid}, "a$_->{aid}";
                    txt_ ']';
                };
            } else {
                b_ sub {
                    txt_ '[';
                    a_ href => "https://anidb.net/anime/$_->{aid}", title => 'AniDB', 'DB';
                    if($_->{ann_id}) {
                        txt_ '-';
                        a_ href => "http://www.animenewsnetwork.com/encyclopedia/anime.php?id=$_->{ann_id}", title => 'Anime News Network', 'ANN';
                    }
                    txt_ '] ';
                };
                abbr_ title => $_->{title_kanji}||$_->{title_romaji}, shorten $_->{title_romaji}, 50;
                b_ ' ('.(defined $_->{type} ? $ANIME_TYPE{$_->{type}}{txt}.', ' : '').$_->{year}.')';
            }
        }, sort { ($a->{year}||9999) <=> ($b->{year}||9999) } $v->{anime}->@* }
    }
}


sub infobox_tags_ {
    my($v) = @_;
    div_ id => 'tagops', sub {
        debug_ $v->{tags};
        for (keys %TAG_CATEGORY) {
            input_ id => "cat_$_", type => 'checkbox', class => 'visuallyhidden',
                (auth ? auth->pref("tags_$_") : $_ ne 'ero') ? (checked => 'checked') : ();
            label_ for => "cat_$_", lc $TAG_CATEGORY{$_};
        }
        my $spoiler = auth->pref('spoilers') || 0;
        input_ id => 'tag_spoil_none', type => 'radio', class => 'visuallyhidden', name => 'tag_spoiler', $spoiler == 0 ? (checked => 'checked') : ();
        label_ for => 'tag_spoil_none', class => 'sec', 'hide spoilers';
        input_ id => 'tag_spoil_some', type => 'radio', class => 'visuallyhidden', name => 'tag_spoiler', $spoiler == 1 ? (checked => 'checked') : ();
        label_ for => 'tag_spoil_some', 'show minor spoilers';
        input_ id => 'tag_spoil_all', type => 'radio', class => 'visuallyhidden', name => 'tag_spoiler', $spoiler == 2 ? (checked => 'checked') : ();
        label_ for => 'tag_spoil_all', 'spoil me!';

        input_ id => 'tag_toggle_summary', type => 'radio', class => 'visuallyhidden', name => 'tag_all', auth->pref('tags_all') ? () : (checked => 'checked');
        label_ for => 'tag_toggle_summary', class => 'sec', 'summary';
        input_ id => 'tag_toggle_all', type => 'radio', class => 'visuallyhidden', name => 'tag_all', auth->pref('tags_all') ? (checked => 'checked') : ();
        label_ for => 'tag_toggle_all', class => 'lst', 'all';
        div_ id => 'vntags', sub {
            my %counts = map +($_,[0,0,0]), keys %TAG_CATEGORY;
            join_ ' ', sub {
                my $spoil = $_->{spoiler} > 1.3 ? 2 : $_->{spoiler} > 0.4 ? 1 : 0;
                my $cnt = $counts{$_->{cat}};
                $cnt->[2]++;
                $cnt->[1]++ if $spoil < 2;
                $cnt->[0]++ if $spoil < 1;
                my $cut = $cnt->[0] > 15 ? ' cut cut2 cut1 cut0' : $cnt->[1] > 15 ? ' cut cut2 cut1' : $cnt->[2] > 15 ? ' cut cut2' : '';
                span_ class => "tagspl$spoil cat_$_->{cat} $cut", sub {
                    a_ href => "/g$_->{id}", style => sprintf('font-size: %dpx', $_->{rating}*3.5+6), $_->{name};
                    spoil_ $spoil;
                    b_ class => 'grayedout', sprintf ' %.1f', $_->{rating};
                }
            }, $v->{tags}->@*;
        }
    }
}


sub infobox_useroptions_ {
    my($v) = @_;
    return if !auth;

    my $labels = tuwf->dbAlli('
        SELECT l.id, l.label, l.private, uvl.vid IS NOT NULL as assigned
          FROM ulist_labels l
          LEFT JOIN ulist_vns_labels uvl ON uvl.uid = l.uid AND uvl.lbl = l.id AND uvl.vid =', \$v->{id}, '
         WHERE l.uid =', \auth->uid,  '
         ORDER BY CASE WHEN l.id < 10 THEN l.id ELSE 10 END, l.label'
    );
    my $lst = tuwf->dbRowi('SELECT vid, vote, notes FROM ulist_vns WHERE uid =', \auth->uid, 'AND vid =', \$v->{id});
    my $review = tuwf->dbVali('SELECT id FROM reviews WHERE uid =', \auth->uid, 'AND vid =', \$v->{id});

    tr_ class => 'nostripe', sub {
        td_ colspan => 2, sub {
            elm_ 'UList.VNPage', $VNWeb::ULists::Elm::VNPAGE, {
                uid      => auth->uid,
                vid      => $v->{id},
                onlist   => $lst->{vid}||0,
                canvote  => canvote($v),
                vote     => fmtvote($lst->{vote}),
                notes    => $lst->{notes}||'',
                review   => $review,
                canreview=> $review || (canvote($v) && can_edit(w => {})),
                labels   => $labels,
                selected => [ map $_->{id}, grep $_->{assigned}, @$labels ],
            };
        }
    }
}


# Also used by Chars::VNTab & Reviews::VNTab
sub infobox_ {
    my($v, $notags) = @_;
    div_ class => 'mainbox', sub {
        itemmsg_ $v;
        h1_ $v->{title};
        h2_ class => 'alttitle', lang_attr($v->{olang}), $v->{original} if $v->{original};

        div_ class => 'vndetails', sub {
            div_ class => 'vnimg', sub { image_ $v->{image}, alt => $v->{title}; };

            table_ class => 'stripe', sub {
                tr_ sub {
                    td_ class => 'key', 'Title';
                    td_ class => 'title', sub {
                        txt_ $v->{title};
                        debug_ $v;
                        abbr_ class => "icons lang $v->{olang}", title => "Original language: $LANGUAGE{$v->{olang}}", '';
                    };
                };

                tr_ sub {
                    td_ 'Original title';
                    td_ lang_attr($v->{olang}), $v->{original};
                } if $v->{original};

                tr_ sub {
                    td_ 'Aliases';
                    td_ $v->{alias} =~ s/\n/, /gr;
                } if $v->{alias};

                tr_ sub {
                    td_ 'Length';
                    td_ "$VN_LENGTH{$v->{length}}{txt} ($VN_LENGTH{$v->{length}}{time})";
                } if $v->{length};

                infobox_producers_ $v;
                infobox_relations_ $v;

                tr_ sub {
                    td_ 'Links';
                    td_ sub { join_ ', ', sub { a_ href => $_->[1], $_->[0] }, $v->{extlinks}->@* };
                } if $v->{extlinks}->@*;

                infobox_affiliates_ $v;
                infobox_anime_ $v;
                infobox_useroptions_ $v;

                tr_ class => 'nostripe', sub {
                    td_ class => 'vndesc', colspan => 2, sub {
                        h2_ 'Description';
                        p_ sub { lit_ $v->{desc} ? bb_format $v->{desc} : '-' };
                    }
                }
            }
        };
        div_ class => 'clearfloat', style => 'height: 5px', ''; # otherwise the tabs below aren't positioned correctly
        infobox_tags_ $v if $v->{tags}->@* && !$notags;
    }
}


# Also used by Chars::VNTab & Reviews::VNTab
sub tabs_ {
    my($v, $tab) = @_;
    my $chars = tuwf->dbVali('SELECT COUNT(DISTINCT c.id) FROM chars c JOIN chars_vns cv ON cv.id = c.id WHERE NOT c.hidden AND cv.vid =', \$v->{id});

    return if !$chars && !$v->{reviews}{full} && !$v->{reviews}{mini} && !auth->permEdit && !auth->permReview;
    $tab ||= '';
    div_ class => 'maintabs', sub {
        ul_ sub {
            li_ class => ($tab eq ''        ? ' tabselected' : ''), sub { a_ href => "/$v->{id}#main", name => 'main', 'main' };
            li_ class => ($tab eq 'tags'    ? ' tabselected' : ''), sub { a_ href => "/$v->{id}/tags#tags", name => 'tags', 'tags' };
            li_ class => ($tab eq 'chars'   ? ' tabselected' : ''), sub { a_ href => "/$v->{id}/chars#chars", name => 'chars', "characters ($chars)" } if $chars;
            if($v->{reviews}{mini} > 4 || $tab eq 'minireviews' || $tab eq 'fullreviews') {
                li_ class => ($tab eq 'minireviews'?' tabselected' : ''), sub { a_ href => "/$v->{id}/minireviews#review", name => 'review', "mini reviews ($v->{reviews}{mini})" } if $v->{reviews}{mini};
                li_ class => ($tab eq 'fullreviews'?' tabselected' : ''), sub { a_ href => "/$v->{id}/fullreviews#review", name => 'review', "full reviews ($v->{reviews}{full})" } if $v->{reviews}{full};
            } elsif($v->{reviews}{mini} || $v->{reviews}{full}) {
                li_ class => ($tab =~ /reviews/ ?' tabselected':''),      sub { a_ href => "/$v->{id}/reviews#review", name => 'review', sprintf 'reviews (%d)', $v->{reviews}{total} };
            }
        };
        ul_ sub {
            if(auth && canvote $v) {
                my $id = tuwf->dbVali('SELECT id FROM reviews WHERE vid =', \$v->{id}, 'AND uid =', \auth->uid);
                li_ sub { a_ href => "/$v->{id}/addreview", 'add review' } if !$id && can_edit w => {};
                li_ sub { a_ href => "/$id/edit", 'edit review' } if $id;
            }
            if(auth->permEdit) {
                li_ sub { a_ href => "/$v->{id}/add", 'add release' };
                li_ sub { a_ href => "/$v->{id}/addchar", 'add character' };
            }
        };
    }
}


sub releases_ {
    my($v) = @_;

    # TODO: Organize a long list of releases a bit better somehow? Collapsable language sections?

    enrich_release $v->{releases};
    $v->{releases} = [ sort { $a->{released} <=> $b->{released} || idcmp($a->{id}, $b->{id}) } $v->{releases}->@* ];
    my %lang;
    my @lang = grep !$lang{$_}++, map +(sort { ($b eq $v->{olang}) cmp ($a eq $v->{olang}) || $a cmp $b } $_->{lang}->@*), $v->{releases}->@*;

    my sub lang_ {
        my($lang) = @_;
        tr_ class => 'lang', sub {
            td_ colspan => 7, sub {
                abbr_ class => "icons lang $lang", title => $LANGUAGE{$lang}, '';
                txt_ $LANGUAGE{$lang};
            }
        };
        my $ropt = { id => $lang };
        release_row_ $_, $ropt for grep grep($_ eq $lang, $_->{lang}->@*), $v->{releases}->@*;
    }

    div_ class => 'mainbox', sub {
        h1_ 'Releases';
        if(!$v->{releases}->@*) {
            p_ 'We don\'t have any information about releases of this visual novel yet...';
        } else {
            table_ class => 'releases', sub { lang_ $_ for @lang };
        }
    }
}


sub staff_ {
    my($v) = @_;

    # XXX: The staff listing is included in the page 3 times, for 3 different
    # layouts. A better approach to get the same layout is to add the boxes to
    # the HTML once with classes indicating the box position (e.g.
    # "4col-col1-row1 3col-col2-row1" etc) and then using CSS to position the
    # box appropriately. My attempts to do this have failed, however. The
    # layouting can also be done in JS, but that's not my preferred option.

    # Step 1: Get a list of 'boxes'; Each 'box' represents a role with a list of staff entries.
    # @boxes = [ $height, $roleimp, $html ]
    my %roles;
    push $roles{$_->{role}}->@*, $_ for grep $_->{sid}, $v->{staff}->@*;
    my $i=0;
    my @boxes =
        sort { $b->[0] <=> $a->[0] || $a->[1] <=> $b->[1] }
        map [ 2+$roles{$_}->@*, $i++,
            xml_string sub {
                li_ class => 'vnstaff_head', $CREDIT_TYPE{$_};
                li_ sub {
                    a_ href => "/$_->{sid}", title => $_->{original}||$_->{name}, $_->{name};
                    b_ title => $_->{note}, class => 'grayedout', $_->{note} if $_->{note};
                } for sort { $a->{name} cmp $b->{name} } $roles{$_}->@*;
            }
        ], grep $roles{$_}, keys %CREDIT_TYPE;

    # Step 2. Assign boxes to columns for 2 to 4 column layouts,
    # efficiently packing the boxes to use the least vertical space,
    # sorting the columns and boxes within columns by role importance.
    # (There is no 1-column layout, that's just the 2-column layout stacked with css)
    my @cols = map [map [0,99,[]], 1..$_], 2..4; # [ $height, $min_roleimp, $boxes ] for each column in each layout
    for my $c (@cols) {
        for (@boxes) {
            my $smallest = $c->[0];
            $c->[$_][0] < $smallest->[0] && ($smallest = $c->[$_]) for 1..$#$c;
            $smallest->[0] += $_->[0];
            $smallest->[1] = $_->[1] if $_->[1] < $smallest->[1];
            push $smallest->[2]->@*, $_;
        }
        $_->[2] = [ sort { $a->[1] <=> $b->[1] } $_->[2]->@* ] for @$c;
        @$c = sort { $a->[1] <=> $b->[1] } @$c;
    }

    div_ class => 'mainbox', id => 'staff', 'data-mainbox-summarize' => 200, sub {
        h1_ 'Staff';
        div_ class => sprintf('vnstaff vnstaff-%d', scalar @$_), sub {
            ul_ sub {
                lit_ $_->[2] for $_->[2]->@*;
            } for @$_
        } for @cols;
    } if $v->{staff}->@*;
}


sub charsum_ {
    my($v) = @_;

    my $spoil = viewget->{spoilers};
    my $c = tuwf->dbAlli('
        SELECT c.id, c.name, c.original, c.gender, v.role
          FROM chars c
          JOIN (SELECT id, MIN(role) FROM chars_vns WHERE role <> \'appears\' AND spoil <=', \$spoil, 'AND vid =', \$v->{id}, 'GROUP BY id) v(id,role) ON c.id = v.id
         WHERE NOT c.hidden
         ORDER BY v.role, c.name, c.id'
    );
    return if !@$c;
    enrich seiyuu => id => cid => sub { sql('
        SELECT vs.cid, sa.id, sa.name, sa.original, vs.note
          FROM vn_seiyuu vs
          JOIN staff_alias sa ON sa.aid = vs.aid
         WHERE vs.id =', \$v->{id}, 'AND vs.cid IN', $_, '
         ORDER BY sa.name'
    ) }, $c;

    div_ class => 'mainbox', 'data-mainbox-summarize' => 200, sub {
        p_ class => 'mainopts', sub {
            a_ href => "/$v->{id}/chars#chars", 'Full character list';
        };
        h1_ 'Character summary';
        div_ class => 'charsum_list', sub {
            div_ class => 'charsum_bubble', sub {
                div_ class => 'name', sub {
                    span_ sub {
                        abbr_ class => "icons gen $_->{gender}", title => $GENDER{$_->{gender}}, '' if $_->{gender} ne 'unknown';
                        a_ href => "/$_->{id}", title => $_->{original}||$_->{name}, $_->{name};
                    };
                    i_ $CHAR_ROLE{$_->{role}}{txt};
                };
                div_ class => 'actor', sub {
                    txt_ 'Voiced by';
                    $_->{seiyuu}->@* > 1 ? br_ : txt_ ' ';
                    join_ \&br_, sub {
                        a_ href => "/$_->{id}", title => $_->{original}||$_->{name}, $_->{name};
                        b_ class => 'grayedout', $_->{note} if $_->{note};
                    }, $_->{seiyuu}->@*;
                } if $_->{seiyuu}->@*;
            } for @$c;
        };
    };
}


sub stats_ {
    my($v) = @_;

    my $stats = tuwf->dbAlli('
        SELECT (uv.vote::numeric/10)::int AS idx, COUNT(uv.vote) as votes, SUM(uv.vote) AS total
          FROM ulist_vns uv
         WHERE uv.vote IS NOT NULL
           AND NOT EXISTS(SELECT 1 FROM users u WHERE u.id = uv.uid AND u.ign_votes)
           AND uv.vid =', \$v->{id}, '
         GROUP BY (uv.vote::numeric/10)::int'
    );
    my $sum = sum map $_->{total}, @$stats;
    my $max = max map $_->{votes}, @$stats;
    my $num = sum map $_->{votes}, @$stats;

    my $recent = @$stats && tuwf->dbAlli('
         SELECT uv.vote,', sql_totime('uv.vote_date'), 'as date, ', sql_user(), '
              , NOT EXISTS(SELECT 1 FROM ulist_vns_labels uvl JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl WHERE uvl.uid = uv.uid AND uvl.vid = uv.vid AND NOT ul.private) AS hide_list
           FROM ulist_vns uv
           JOIN users u ON u.id = uv.uid
          WHERE uv.vid =', \$v->{id}, 'AND uv.vote IS NOT NULL
            AND NOT EXISTS(SELECT 1 FROM users u WHERE u.id = uv.uid AND u.ign_votes)
          ORDER BY uv.vote_date DESC
          LIMIT', \($v->{reviews}{total} ? 7 : 8)
    );

    my $rank = $v->{c_votecount} && tuwf->dbRowi('SELECT c_rating, c_popularity, c_pop_rank, c_rat_rank FROM vn v WHERE id =', \$v->{id});

    my sub votestats_ {
        table_ class => 'votegraph', sub {
            thead_ sub { tr_ sub { td_ colspan => 2, 'Vote stats' } };
            tfoot_ sub { tr_ sub { td_ colspan => 2, sprintf '%d vote%s total, average %.2f (%s)', $num, $num == 1 ? '' : 's', $sum/$num/10, fmtrating(floor($sum/$num/10)||1) } };
            tr_ sub {
                my $num = $_;
                my $votes = [grep $num == $_->{idx}, @$stats]->[0]{votes} || 0;
                td_ class => 'number', $num;
                td_ class => 'graph', sub {
                    div_ style => sprintf('width: %dpx', ($votes||0)/$max*250), ' ';
                    txt_ $votes||0;
                };
            } for (reverse 1..10);
        };

        table_ class => 'recentvotes stripe', sub {
            thead_ sub { tr_ sub { td_ colspan => 3, sub {
                txt_ 'Recent votes';
                b_ sub {
                    txt_ '(';
                    a_ href => "/$v->{id}/votes", 'show all';
                    txt_ ')';
                }
            } } };
            tfoot_ sub { tr_ sub { td_ colspan => 3, sub {
                a_ href => "/$v->{id}/reviews#review", sprintf'%d review%s »', $v->{reviews}{total}, $v->{reviews}{total}==1?'':'s';
            } } } if $v->{reviews}{total};
            tr_ sub {
                td_ sub {
                    b_ class => 'grayedout', 'hidden' if $_->{hide_list};
                    user_ $_ if !$_->{hide_list};
                };
                td_ fmtvote $_->{vote};
                td_ fmtdate $_->{date};
            } for @$recent;
        } if $recent && @$recent;

        clearfloat_;
        div_ sub {
            h3_ 'Ranking';
            p_ sprintf 'Popularity: ranked #%d with a score of %.2f', $rank->{c_pop_rank}, $rank->{c_popularity}*100 if defined $rank->{c_popularity};
            p_ sprintf 'Bayesian rating: ranked #%d with a rating of %.2f', $rank->{c_rat_rank}, $rank->{c_rating}/10;
        } if $v->{c_votecount};
    }

    div_ class => 'mainbox', id => 'stats', sub {
        h1_ 'User stats';
        if(!@$stats) {
            p_ 'Nobody has voted on this visual novel yet...';
        } else {
            div_ class => 'votestats', \&votestats_;
        }
    }
}


sub screenshots_ {
    my($v) = @_;
    my $s = $v->{screenshots};
    return if !@$s;

    my $sexp = auth->pref('max_sexual')||0;
    my $viop = auth->pref('max_violence')||0;
    $viop = 0 if $sexp < 0;
    my $sexs = min($sexp, max map $_->{scr}{sexual}, @$s);
    my $vios = min($viop, max map $_->{scr}{violence}, @$s);

    my @sex = (0,0,0);
    my @vio = (0,0,0);
    for (@$s) { $sex[$_->{scr}{sexual}]++; $vio[$_->{scr}{violence}]++ }

    my %rel;
    push $rel{$_->{rid}}->@*, $_ for grep $_->{rid}, @$s;

    input_ name => 'scrhide_s', id => "scrhide_s$_", type => 'radio', class => 'visuallyhidden', $sexs == $_ ? (checked => 'checked') : () for 0..2;
    input_ name => 'scrhide_v', id => "scrhide_v$_", type => 'radio', class => 'visuallyhidden', $vios == $_ ? (checked => 'checked') : () for 0..2;
    div_ class => 'mainbox', id => 'screenshots', sub {

        p_ class => 'mainopts', sub {
            if($sex[1] || $sex[2]) {
                label_ for => 'scrhide_s0', class => 'fake_link', "Safe ($sex[0])";
                label_ for => 'scrhide_s1', class => 'fake_link', "Suggestive ($sex[1])" if $sex[1];
                label_ for => 'scrhide_s2', class => 'fake_link', "Explicit ($sex[2])" if $sex[2];
            }
            b_ class => 'grayedout', ' | ' if ($sex[1] || $sex[2]) && ($vio[1] || $vio[2]);
            if($vio[1] || $vio[2]) {
                label_ for => 'scrhide_v0', class => 'fake_link', "Tame ($vio[0])";
                label_ for => 'scrhide_v1', class => 'fake_link', "Violent ($vio[1])" if $vio[1];
                label_ for => 'scrhide_v2', class => 'fake_link', "Brutal ($vio[2])" if $vio[2];
            }
        } if $sex[1] || $sex[2] || $vio[1] || $vio[2];

        h1_ 'Screenshots';

        for my $r (grep $rel{$_->{id}}, $v->{releases}->@*) {
            p_ class => 'rel', sub {
                abbr_ class => "icons lang $_", title => $LANGUAGE{$_}, '' for $r->{languages}->@*;
                abbr_ class => "icons $_", title => $PLATFORM{$_}, '' for $r->{platforms}->@*;
                a_ href => "/$r->{id}", $r->{title};
            };
            div_ class => 'scr', sub {
                a_ href => imgurl($_->{scr}{id}),
                    'data-iv' => "$_->{scr}{width}x$_->{scr}{height}:scr:$_->{scr}{sexual}$_->{scr}{violence}$_->{scr}{votecount}",
                    mkclass(
                        scrlnk => 1,
                        scrlnk_s0 => $_->{scr}{sexual} <= 0,
                        scrlnk_s1 => $_->{scr}{sexual} <= 1,
                        scrlnk_v0 => $_->{scr}{violence} >= 1,
                        scrlnk_v1 => $_->{scr}{violence} >= 2,
                        nsfw => $_->{scr}{sexual} || $_->{scr}{violence},
                    ),
                sub {
                    my($w, $h) = imgsize $_->{scr}{width}, $_->{scr}{height}, config->{scr_size}->@*;
                    img_ src => imgurl($_->{scr}{id}, 1), width => $w, height => $h, alt => "Screenshot $_->{scr}{id}";
                } for $rel{$r->{id}}->@*;
            }
        }
    }
}


sub tags_ {
    my($v) = @_;
    if(!$v->{tags}->@*) {
        div_ class => 'mainbox', sub {
            h1_ 'Tags';
            p_ 'This VN has no tags assigned to it (yet).';
        };
        return;
    }

    my %tags = map +($_->{id},$_), $v->{tags}->@*;
    my $parents = tuwf->dbAlli("
        WITH RECURSIVE parents (tag, child) AS (
          SELECT tag::int, NULL::int FROM (VALUES", sql_join(',', map sql('(',\$_,')'), keys %tags), ") AS x(tag)
          UNION
          SELECT tp.parent, tp.tag FROM tags_parents tp, parents a WHERE a.tag = tp.tag
        ) SELECT * FROM parents WHERE child IS NOT NULL"
    );

    for(@$parents) {
        $tags{$_->{tag}} ||= { id => $_->{tag} };
        push $tags{$_->{tag}}{childs}->@*, $_->{child};
        $tags{$_->{child}}{notroot} = 1;
    }
    enrich_merge id => 'SELECT id, name, cat FROM tags WHERE id IN', grep !$_->{name}, values %tags;
    my @roots = sort { $a->{name} cmp $b->{name} } grep !$_->{notroot}, values %tags;

    # Calculate rating and spoiler for parent tags.
    my sub scores {
        my($t) = @_;
        return if !$t->{childs};
        __SUB__->($tags{$_}) for $t->{childs}->@*;
        $t->{inherited} = 1 if !defined $t->{rating};
        $t->{spoiler} //= min map $tags{$_}{spoiler}, $t->{childs}->@*;
        $t->{rating} //= sum(map $tags{$_}{rating}, $t->{childs}->@*) / $t->{childs}->@*;
    }
    scores $_ for @roots;
    $_->{spoiler} = $_->{spoiler} > 1.3 ? 2 : $_->{spoiler} > 0.4 ? 1 : 0 for values %tags;

    my $view = viewget;
    my sub rec {
        my($lvl, $t) = @_;
        return if $t->{spoiler} > $view->{spoilers};
        li_ class => "tagvnlist-top", sub {
            h3_ sub { a_ href => "/g$t->{id}", $t->{name} }
        } if !$lvl;

        li_ $lvl == 1 ? (class => 'tagvnlist-parent') : $t->{inherited} ? (class => 'tagvnlist-inherited') : (), sub {
            VNWeb::TT::Lib::tagscore_($t->{rating}, $t->{inherited});
            b_ class => 'grayedout', '━━'x($lvl-1).' ' if $lvl > 1;
            a_ href => "/g$t->{id}", $t->{rating} ? () : (class => 'parent'), $t->{name};
            spoil_ $t->{spoiler};
        } if $lvl;

        if($t->{childs}) {
            __SUB__->($lvl+1, $_) for sort { $a->{name} cmp $b->{name} } map $tags{$_}, $t->{childs}->@*;
        }
    }

    div_ class => 'mainbox', sub {
        my $max_spoil = max map $_->{spoiler}, values %tags;
        p_ class => 'mainopts', sub {
            if($max_spoil) {
                a_ mkclass(checked => $view->{spoilers} == 0), href => '?view='.viewset(spoilers=>0).'#tags', 'Hide spoilers';
                a_ mkclass(checked => $view->{spoilers} == 1), href => '?view='.viewset(spoilers=>1).'#tags', 'Show minor spoilers';
                a_ mkclass(standout =>$view->{spoilers} == 2), href => '?view='.viewset(spoilers=>2).'#tags', 'Spoil me!' if $max_spoil == 2;
            }
        } if $max_spoil;

        h1_ 'Tags';
        ul_ class => 'vntaglist', sub {
            rec 0, $_ for @roots;
        };
        debug_ \%tags;
    };
}


TUWF::get qr{/$RE{vrev}}, sub {
    my $v = db_entry tuwf->captures('id', 'rev');
    return tuwf->resNotFound if !$v;

    enrich_item $v, 1;

    framework_ title => $v->{title}, index => !tuwf->capture('rev'), dbobj => $v, hiddenmsg => 1, js => 1, og => og($v),
    sub {
        rev_ $v if tuwf->capture('rev');
        infobox_ $v;
        tabs_ $v, 0;
        releases_ $v;
        staff_ $v;
        charsum_ $v;
        stats_ $v;
        screenshots_ $v;
    };
};


TUWF::get qr{/$RE{vid}/tags}, sub {
    my $v = db_entry tuwf->capture('id');
    return tuwf->resNotFound if !$v;

    enrich_vn $v;

    framework_ title => $v->{title}, index => 1, dbobj => $v, hiddenmsg => 1,
    sub {
        infobox_ $v, 1;
        tabs_ $v, 'tags';
        tags_ $v;
    };
};

1;
