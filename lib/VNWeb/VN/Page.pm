package VNWeb::VN::Page;

use VNWeb::Prelude;
use VNWeb::Releases::Lib;
use VNWeb::Images::Lib qw/image_flagging_display image_ enrich_image_obj/;
use VNWeb::ULists::Lib 'ulists_widget_full_data';
use VNDB::Func 'fmtrating';


# Enrich everything necessary to at least render infobox_() and tabs_().
# Also used by Chars::VNTab & Reviews::VNTab
sub enrich_vn {
    my($v, $revonly) = @_;
    $v->{title} = titleprefs_obj $v->{olang}, $v->{titles};
    enrich_merge id => 'SELECT id, c_votecount, c_length, c_lengthnum FROM vn WHERE id IN', $v;
    enrich_merge vid => sql('SELECT id AS vid, title, sorttitle, c_released FROM', vnt, 'v WHERE id IN'), $v->{relations};
    enrich_merge aid => 'SELECT id AS aid, title_romaji, title_kanji, year, type, ann_id, lastfetch FROM anime WHERE id IN', $v->{anime};
    enrich_extlinks v => 0, $v;
    enrich_image_obj image => $v;
    enrich_image_obj scr => $v->{screenshots};

    # The queries below are not relevant for revisions
    return if $revonly;

    # This fetches rather more information than necessary for infobox_(), but it'll have to do.
    # (And we'll need it for the releases tab anyway)
    $v->{releases} = tuwf->dbAlli('
        SELECT r.id, rv.rtype, r.patch, r.released, r.gtin,', sql_extlinks(r => 'r.'), '
             , (SELECT COUNT(*) FROM releases_vn rv WHERE rv.id = r.id) AS num_vns
          FROM releases r
          JOIN releases_vn rv ON rv.id = r.id
         WHERE NOT r.hidden AND rv.vid =', \$v->{id}
    );
    enrich_extlinks r => 0, $v->{releases};

    $v->{reviews} = tuwf->dbRowi('
        SELECT COUNT(*) FILTER(WHERE isfull) AS full, COUNT(*) FILTER(WHERE NOT isfull) AS mini, COUNT(*) AS total
          FROM reviews
         WHERE NOT c_flagged AND vid =', \$v->{id}
    );
    $v->{tags} = !prefs()->{has_tagprefs} ? tuwf->dbAlli('
        SELECT t.id, t.name, t.cat, tv.rating, tv.spoiler, tv.lie
          FROM tags t
          JOIN tags_vn_direct tv ON t.id = tv.tag
         WHERE tv.vid =', \$v->{id}, '
         ORDER BY rating DESC, t.name'
    ) : tuwf->dbAlli(
        # Monster of a query, but tag overrides are a bit complicated:
        # - We need to find the shortest path from a tag applied to the VN to a
        #   parent in users_prefs_tags, and use those preferences. That's what
        #   tag_direct does.
        # - If the user has a tag marked as "Always show" but hasn't checked
        #   "also apply to child tags", then we need to look for any child tags
        #   and inject their parent if said parent hasn't been directly applied.
        #   That's what tag_indirect does.
       'WITH RECURSIVE tag_overrides (tid, spoil, color, childs, lvl) AS (
          SELECT tid, spoil, color, childs, 0 FROM users_prefs_tags WHERE id =', \auth->uid, '
           UNION ALL
          SELECT tp.id, x.spoil, x.color, true, lvl+1
            FROM tag_overrides x
            JOIN tags_parents tp ON tp.parent = x.tid
           WHERE x.childs
        ), tag_overrides_grouped (tid, spoil, color) AS (
          SELECT DISTINCT ON(tid) tid, spoil, color FROM tag_overrides ORDER BY tid, lvl
        ), tag_direct (tid, rating, spoiler, lie, override, color) AS (
          SELECT t.tag, t.rating, t.spoiler, t.lie, x.spoil, x.color
            FROM tags_vn_direct t
            LEFT JOIN tag_overrides_grouped x ON x.tid = t.tag
           WHERE t.vid =', \$v->{id}, 'AND x.spoil IS DISTINCT FROM 1+1+1
        ), tag_indirect (tid, rating, spoiler, lie, override, color) AS (
          SELECT t.tag, t.rating, t.spoiler, t.lie, x.spoil, x.color
            FROM tags_vn_inherit t
            JOIN users_prefs_tags x ON x.tid = t.tag
           WHERE t.vid =', \$v->{id}, 'AND x.id =', \auth->uid, 'AND NOT x.childs AND x.spoil = 0
             AND NOT EXISTS(SELECT 1 FROM tag_direct d WHERE d.tid = t.tag)
        ) SELECT t.id, t.name, t.cat, d.rating, d.spoiler, d.lie, d.override, d.color
            FROM tags t
            JOIN (SELECT * FROM tag_direct UNION ALL SELECT * FROM tag_indirect) d ON d.tid = t.id
           ORDER BY d.rating DESC, t.name'
    );
}


# Enrich everything necessary for rev_() (includes enrich_vn())
sub enrich_item {
    my($v, $full) = @_;
    enrich_vn $v, !$full;
    enrich_merge aid => sql('SELECT id AS sid, aid, title FROM', staff_aliast, 's WHERE aid IN'), $v->{staff}, $v->{seiyuu};
    enrich_merge cid => sql('SELECT id AS cid, title AS char_title FROM', charst, 'c WHERE id IN'), $v->{seiyuu};

    $v->{relations}   = [ sort { idcmp($a->{vid}, $b->{vid}) } $v->{relations}->@* ];
    $v->{anime}       = [ sort { $a->{aid} <=> $b->{aid} } $v->{anime}->@* ];
    $v->{editions}    = [ sort { ($a->{lang}||'') cmp ($b->{lang}||'') || $b->{official} cmp $a->{official} || $a->{name} cmp $b->{name} } $v->{editions}->@* ];
    $v->{staff}       = [ sort { ($a->{eid}//-1) <=> ($b->{eid}//-1) || $a->{aid} <=> $b->{aid} || $a->{role} cmp $b->{role} } $v->{staff}->@* ];
    $v->{seiyuu}      = [ sort { $a->{aid} <=> $b->{aid} || idcmp($a->{cid}, $b->{cid}) || $a->{note} cmp $b->{note} } $v->{seiyuu}->@* ];
    $v->{screenshots} = [ sort { idcmp($a->{scr}{id}, $b->{scr}{id}) } $v->{screenshots}->@* ];
}


sub og {
    my($v) = @_;
    +{
        description => bb_format($v->{description}, text => 1),
        image => $v->{image} && !$v->{image}{sexual} && !$v->{image}{violence} ? imgurl($v->{image}{id}) :
                 [map $_->{scr}{sexual}||$_->{scr}{violence}?():(imgurl($_->{scr}{id})), $v->{screenshots}->@*]->[0]
    }
}


sub prefs {
    state $default = {
        vnrel_langs   => \%LANGUAGE, vnrel_olang   => 1, vnrel_mtl     => 0,
        staffed_langs => \%LANGUAGE, staffed_olang => 1, staffed_unoff => 0,
        has_tagprefs => 0,
    };
    tuwf->req->{vnpage_prefs} //= auth ? do {
        my $v = tuwf->dbRowi('
            SELECT vnrel_langs::text[], vnrel_olang, vnrel_mtl
                 , staffed_langs::text[], staffed_olang, staffed_unoff
                 , EXISTS(SELECT 1 FROM users_prefs_tags WHERE id =', \auth->uid, ') AS has_tagprefs
              FROM users_prefs
             WHERE id =', \auth->uid
        );
        $v->{vnrel_langs} = $v->{vnrel_langs} ? { map +($_,1), $v->{vnrel_langs}->@* } : \%LANGUAGE;
        $v->{staffed_langs} = $v->{staffed_langs} ? { map +($_,1), $v->{staffed_langs}->@* } : \%LANGUAGE;
        $v
    } : $default;
}


# The voting and review options are hidden if nothing has been released yet.
sub canvote {
    my($v) = @_;
    $v->{_canvote} //= do {
        my $minreleased = min grep $_, map $_->{released}, $v->{releases}->@*;
        $minreleased && $minreleased <= strftime('%Y%m%d', gmtime)
    };
}


sub rev_ {
    my($v) = @_;
    revision_ $v, \&enrich_item,
        [ titles      => 'Title(s)',      txt => sub {
            "[$_->{lang}] $_->{title}".($_->{latin} ? " / $_->{latin}" : '').($_->{official} ? '' : ' (unofficial)')
        }],
        [ alias       => 'Alias'          ],
        [ olang       => 'Original language', fmt => \%LANGUAGE ],
        [ description => 'Description'    ],
        [ devstatus   => 'Development status',fmt => \%DEVSTATUS ],
        [ length      => 'Length',        fmt => \%VN_LENGTH ],
        [ editions    => 'Editions',      fmt => sub {
            abbr_ class => "icon-lang-$_->{lang}", title => $LANGUAGE{$_->{lang}}{txt}, '' if $_->{lang};
            txt_ $_->{name};
            small_ ' (unofficial)' if !$_->{official};
        }],
        [ staff       => 'Credits',       fmt => sub {
            my $eid = $_->{eid};
            my $e = defined $eid && (grep $eid == $_->{eid}, $_[0]{editions}->@*)[0];
            txt_ "[$e->{name}] " if $e;
            a_ href => "/$_->{sid}", tattr $_ if $_->{sid};
            small_ '[removed alias]' if !$_->{sid};
            txt_ " [$CREDIT_TYPE{$_->{role}}]";
            txt_ " [$_->{note}]" if $_->{note};
        }],
        [ seiyuu      => 'Seiyuu',        fmt => sub {
            a_ href => "/$_->{sid}", tattr $_ if $_->{sid};
            small_ '[removed alias]' if !$_->{sid};
            txt_ ' as ';
            a_ href => "/$_->{cid}", tattr $_->{char_title};
            txt_ " [$_->{note}]" if $_->{note};
        }],
        [ relations   => 'Relations',     fmt => sub {
            txt_ sprintf '[%s] %s: ', $_->{official} ? 'official' : 'unofficial', $VN_RELATION{$_->{relation}}{txt};
            a_ href => "/$_->{vid}", tattr $_;
        }],
        [ anime       => 'Anime',         fmt => sub { a_ href => "https://anidb.net/anime/$_->{aid}", "a$_->{aid}" }],
        [ screenshots => 'Screenshots',   fmt => sub {
            my $rev = $_[0]{chid} == $v->{chid} ? 'new' : 'old';
            txt_ '[';
            a_ href => "/$_->{rid}", $_->{rid} if $_->{rid};
            txt_ 'no release' if !$_->{rid};
            txt_ '] ';
            a_ href => imgurl($_->{scr}{id}), 'data-iv' => "$_->{scr}{width}x$_->{scr}{height}:$rev:$_->{scr}{sexual}$_->{scr}{violence}$_->{scr}{votecount}", $_->{scr}{id};
            txt_ " [$_->{scr}{width}x$_->{scr}{height}; ";
            a_ href => "/img/$_->{scr}{id}", image_flagging_display $_->{scr};
            txt_ '] ';
            # The old NSFW flag has been removed around 2020-07-14, so not relevant for edits made later on.
            small_ sprintf 'old flag: %s', $_->{nsfw} ? 'NSFW' : 'Safe' if $_[0]{rev_added} < 1594684800;
        }],
        [ image       => 'Image',         fmt => sub { image_ $_ } ],
        [ img_nsfw    => 'Image NSFW (unused)', fmt => sub { txt_ $_ ? 'Not safe' : 'Safe' } ],
        revision_extlinks 'v'
}


sub infobox_relations_ {
    my($v) = @_;
    return if !$v->{relations}->@*;

    my %rel;
    push $rel{$_->{relation}}->@*, $_ for sort { $b->{official} <=> $a->{official} || $a->{c_released} <=> $b->{c_released} || $a->{sorttitle} cmp $b->{sorttitle} } $v->{relations}->@*;
    my $unoffcount = grep !$_->{official}, $v->{relations}->@*;

    tr_ sub {
        td_ 'Relations';
        td_ class => 'relations linkradio', sub {
            if($unoffcount >= 3) {
                input_ type => 'checkbox', id => 'unoffrelations', class => 'visuallyhidden';
                label_ for => 'unoffrelations', "unofficial ($unoffcount)";
            }
            dl_ sub {
                for(sort keys %rel) {
                    my @allunoff = (!grep $_->{official}, $rel{$_}->@*) ? (class => 'unofficial') : ();
                    dt_ @allunoff, $VN_RELATION{$_}{txt};
                    dd_ @allunoff, sub {
                        p_ class => $_->{official} ? undef : 'unofficial', sub {
                            small_ '[unofficial] ' if !$_->{official};
                            a_ href => "/$_->{vid}", tattr $_;
                        } for $rel{$_}->@*;
                    }
                }
            }
        }
    }
}


sub infobox_length_ {
    my($v) = @_;

    tr_ sub {
        td_ 'Play time';
        td_ sub {
            # Cached number, which means this VN has counted votes
            if($v->{c_lengthnum}) {
                my $m = $v->{c_length};
                txt_ +(grep $m >= $_->{low} && $m < $_->{high}, values %VN_LENGTH)[0]{txt}.' (';
                vnlength_ $m;
                txt_ ' from ';
                a_ href => "/$v->{id}/lengthvotes", sprintf '%d vote%s', $v->{c_lengthnum}, $v->{c_length}==1?'':'s';
                txt_ ')';
            # No cached number so no counted votes; fall back to old 'length' field and display number of uncounted votes
            } else {
                my $uncounted = tuwf->dbVali('SELECT count(*) FROM vn_length_votes WHERE vid =', \$v->{id}, 'AND NOT private');
                txt_ $VN_LENGTH{$v->{length}}{txt};
                if ($v->{length} || $uncounted) {
                    lit_ ' (';
                    txt_ $VN_LENGTH{$v->{length}}{time} if $v->{length};
                    lit_ ', ' if $v->{length} && $uncounted;
                    a_ href => "/$v->{id}/lengthvotes", sprintf '%d uncounted vote%s', $uncounted, $uncounted == 1 ? '' : 's' if $uncounted;
                    lit_ ')';
                }
            }
            if (VNWeb::VN::Length::can_vote()) {
                my $my = tuwf->dbRowi('SELECT rid::text[] AS rid, length, speed, private, notes FROM vn_length_votes WHERE vid =', \$v->{id}, 'AND uid =', \auth->uid);
                elm_ VNLengthVote => $VNWeb::VN::Length::LENGTHVOTE, {
                    uid => auth->uid, vid => $v->{id},
                    vote => $my->{rid}?$my:undef,
                    maycount => $v->{devstatus} != 1,
                }, sub { span_ @_, ''};
            }
        };
    };
}


sub infobox_producers_ {
    my($v) = @_;

    my $p = tuwf->dbAlli('
        SELECT p.id, p.title, p.sorttitle, rl.lang, bool_or(rp.developer) as developer, bool_or(rp.publisher) as publisher, min(rv.rtype) as rtype, bool_or(r.official) as official
          FROM releases_vn rv
          JOIN releases r ON r.id = rv.id
          JOIN releases_titles rl ON rl.id = rv.id
          JOIN releases_producers rp ON rp.id = rv.id
          JOIN', producerst, 'p ON p.id = rp.pid
         WHERE NOT r.hidden AND (r.official OR NOT rl.mtl) AND rv.vid =', \$v->{id}, '
         GROUP BY p.id, p.title, p.sorttitle, rl.lang
         ORDER BY NOT bool_or(r.official), MIN(r.released), p.sorttitle
    ');
    return if !@$p;

    my $hasfull = grep $_->{rtype} eq 'complete', @$p;
    my %dev;
    my @dev = grep $_->{developer} && (!$hasfull || $_->{rtype} ne 'trial') && !$dev{$_->{id}}++, @$p;

    tr_ sub {
        td_ 'Developer';
        td_ sub {
            join_ ' & ', sub { a_ href => "/$_->{id}", tattr $_ }, @dev;
        };
    } if @dev;

    my(%lang, @lang, $lang);
    for(grep $_->{publisher} && (!$hasfull || $_->{rtype} ne 'trial'), @$p) {
        push @lang, $_->{lang} if !$lang{$_->{lang}};
        push $lang{$_->{lang}}->@*, $_;
    }
    return if !keys %lang;

    use sort 'stable';
    @lang = sort { ($b eq $v->{olang}) cmp ($a eq $v->{olang}) } @lang;

    # Merge multiple languages into one group if the publishers are the same.
    my @nlang = (shift @lang);
    my $last = join ';', sort map $_->{id}, $lang{$nlang[0]}->@*;
    for (@lang) {
        my $cids = join ';', sort map $_->{id}, $lang{$_}->@*;
        if($last eq $cids) {
            $nlang[$#nlang] .= ";$_";
        } else {
            push @nlang, $_;
        }
        $last = $cids;
    }

    tr_ sub {
        td_ 'Publishers';
        td_ sub {
            join_ \&br_, sub {
                my @l = split /;/;
                abbr_ class => "icon-lang-$_", title => $LANGUAGE{$_}{txt}, '' for @l;
                join_ ' & ', sub { a_ href => "/$_->{id}", $_->{official} ? () : (class => 'grayedout'), tattr $_ }, $lang{$l[0]}->@*;
            }, @nlang;
        }
    };
}


sub infobox_affiliates_ {
    my($v) = @_;

    # If the same shop link has been added to multiple releases, use the 'first' matching type in this list.
    my @type = ('bundle', '', 'partial', 'trial', 'patch');

    # url => [$title, $url, $price, $type]
    my %links;
    for my $rel ($v->{releases}->@*) {
        my $type =     $rel->{patch} ? 4 :
            $rel->{rtype} eq 'trial' ? 3 :
          $rel->{rtype} eq 'partial' ? 2 :
                 $rel->{num_vns} > 1 ? 0 : 1;

        $links{$_->{url2}} = [ @{$_}{qw/label url2 price/}, min $type, $links{$_->{url2}}[3]||9 ] for grep $_->{price}, $rel->{extlinks}->@*;
    }
    return if !keys %links;

    tr_ id => 'buynow', sub {
        td_ 'Shops';
        td_ sub {
            join_ \&br_, sub {
                b_ '» ';
                a_ href => $_->[1], sub {
                    txt_ $_->[2];
                    small_ ' @ ';
                    txt_ $_->[0];
                    small_ " ($type[$_->[3]])" if $_->[3] != 1;
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
                span_ sub {
                    txt_ '[no information available at this time: ';
                    a_ href => 'https://anidb.net/anime/'.$_->{aid}, "a$_->{aid}";
                    txt_ ']';
                };
            } else {
                span_ sub {
                    txt_ '[';
                    a_ href => "https://anidb.net/anime/$_->{aid}", title => 'AniDB', 'DB';
                    if($_->{ann_id}) {
                        txt_ '-';
                        a_ href => "http://www.animenewsnetwork.com/encyclopedia/anime.php?id=$_->{ann_id}", title => 'Anime News Network', 'ANN';
                    }
                    txt_ '] ';
                };
                abbr_ title => $_->{title_kanji}||$_->{title_romaji}, shorten $_->{title_romaji}, 50;
                span_ ' ('.(defined $_->{type} ? $ANIME_TYPE{$_->{type}}{txt}.', ' : '').$_->{year}.')';
            }
        }, sort { ($a->{year}||9999) <=> ($b->{year}||9999) } $v->{anime}->@* }
    }
}


sub infobox_tags_ {
    my($v) = @_;
    div_ id => 'tagops', sub {
        debug_ $v->{tags};
        my @ero = grep($_->{cat} eq 'ero', $v->{tags}->@*) ? ('ero') : ();
        for ('cont', @ero, 'tech') {
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
                my $spoil = $_->{override}//$_->{spoiler};
                my $cnt = $counts{$_->{cat}};
                $cnt->[2]++;
                $cnt->[1]++ if $spoil < 2;
                $cnt->[0]++ if $spoil < 1;
                my $cut = defined $_->{override} ? '' : $cnt->[0] > 15 ? ' cut cut2 cut1 cut0' : $cnt->[1] > 15 ? ' cut cut2 cut1' : $cnt->[2] > 15 ? ' cut cut2' : '';
                span_ class => "tagspl$spoil cat_$_->{cat} $cut", sub {
                    a_ href => "/$_->{id}",
                        mkclass(defined $_->{override} ? 'lieo' : 'lie', $_->{lie},
                                $_->{color} ? ($_->{color}, $_->{color} =~ /standout|grayedout/ ? 1 : 0) : ()),
                        style => sprintf('font-size: %dpx', $_->{rating}*3.5+6)
                                 .(($_->{color}//'') =~ /^#/ ? "; color: $_->{color}" : ''),
                        $_->{name};
                    spoil_ $_->{spoiler};
                    small_ sprintf ' %.1f', $_->{rating};
                }
            }, $v->{tags}->@*;
        }
    }
}


# Also used by Chars::VNTab & Reviews::VNTab
sub infobox_ {
    my($v, $notags) = @_;

    sub tlang_ {
        my($t) = @_;
        tr_ mkclass(title => 1, grayedout => !$t->{official}), sub {
            td_ sub {
                abbr_ class => "icon-lang-$t->{lang}", title => $LANGUAGE{$t->{lang}}{txt}, '';
            };
            td_ sub {
                span_ tlang($t->{lang}, $t->{title}), $t->{title};
                if($t->{latin}) {
                    br_;
                    txt_ $t->{latin};
                }
            }
        }
    }

    article_ sub {
        itemmsg_ $v;
        h1_ tlang($v->{title}[0], $v->{title}[1]), $v->{title}[1];
        h2_ class => 'alttitle', tlang(@{$v->{title}}[2,3]), $v->{title}[3] if $v->{title}[3] && $v->{title}[3] ne $v->{title}[1];

        div_ class => 'warning', sub {
            h2_ 'No releases';
            p_ sub {
                txt_ 'This entry does not have any releases associated with it yet. Please ';
                a_ href => "/$v->{id}/add", 'add a release entry';
                txt_ ' if you have information about this visual novel.';
                br_;
                txt_ '(A release entry should be present even if nothing has been
                    released yet, in that case it can just be a placeholder for a
                    future release)';
            };
        } if !$v->{hidden} && auth->permEdit && !$v->{releases}->@*;

        p_ class => 'center standout', sub { lit_ config->{special_games}{$v->{id}}; br_; br_ } if config->{special_games}{$v->{id}};

        div_ class => 'vndetails', sub {
            div_ class => 'vnimg', sub { image_ $v->{image}, alt => $v->{title}[1]; };

            table_ class => 'stripe', sub {
                tr_ sub {
                    td_ 'Title';
                    td_ sub {
                        table_ sub { tlang_ $v->{titles}[0] };
                    };
                } if $v->{titles}->@* == 1;
                tr_ sub {
                    td_ class => 'titles', colspan => 2, sub {
                        details_ sub {
                            summary_ sub {
                                div_ 'Titles';
                                table_ sub { tlang_ grep $_->{lang} eq $v->{olang}, $v->{titles}->@* };
                            };
                            table_ sub {
                                tlang_ $_ for grep $_->{lang} ne $v->{olang}, sort { $b->{official} cmp $a->{official} || $a->{lang} cmp $b->{lang} } $v->{titles}->@*;
                            };
                        };
                    };
                } if $v->{titles}->@* > 1;

                tr_ sub {
                    td_ 'Aliases';
                    td_ $v->{alias} =~ s/\n/, /gr;
                } if $v->{alias};

                tr_ sub {
                    td_ 'Status';
                    td_ sub {
                        txt_ 'In development' if $v->{devstatus} == 1;
                        txt_ 'Unfinished, no ongoing development' if $v->{devstatus} == 2;
                    };
                } if $v->{devstatus};

                infobox_length_ $v;
                infobox_producers_ $v;
                infobox_relations_ $v;

                tr_ sub {
                    td_ 'Links';
                    td_ sub { join_ ', ', sub { a_ href => $_->{url2}, $_->{label} }, $v->{extlinks}->@* };
                } if $v->{extlinks}->@*;

                infobox_affiliates_ $v;
                infobox_anime_ $v;

                tr_ class => 'nostripe', sub {
                    td_ colspan => 2, sub {
                        elm_ 'UList.VNPage', $VNWeb::ULists::Elm::WIDGET,
                        ulists_widget_full_data $v, auth->uid, 1, canvote $v;
                    }
                } if auth;

                tr_ class => 'nostripe', sub {
                    td_ class => 'vndesc', colspan => 2, sub {
                        h2_ 'Description';
                        p_ sub { lit_ $v->{description} ? bb_format $v->{description} : '-' };
                        debug_ $v;
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
    nav_ sub {
        menu_ sub {
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
        menu_ sub {
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

    enrich_release $v->{releases};
    $v->{releases} = sort_releases $v->{releases};

    my(%lang, %langrel, %langmtl);
    for my $r ($v->{releases}->@*) {
        for ($r->{titles}->@*) {
            push $lang{$_->{lang}}->@*, $r;
            $langmtl{$_->{lang}} = ($langmtl{$_->{lang}}//1) && $_->{mtl};
        }
    }
    $langrel{$_} = min map $_->{released}, $lang{$_}->@* for keys %lang;
    my @lang = sort { $langrel{$a} <=> $langrel{$b} || ($b eq $v->{olang}) cmp ($a eq $v->{olang}) || $a cmp $b } keys %lang;
    my $pref = prefs;

    my sub lang_ {
        my($lang) = @_;
        my $ropt = { id => $lang, lang => $lang };
        my $mtl = $langmtl{$lang};
        my $open = ($pref->{vnrel_olang} && $lang eq $v->{olang} && !$mtl) || ($pref->{vnrel_langs}{$lang} && (!$mtl || $pref->{vnrel_mtl}));
        details_ open => $open?'open':undef, sub {
            summary_ $mtl ? (class => 'mtl') : (), sub {
                abbr_ class => "icon-lang-$lang".($mtl?' mtl':''), title => $LANGUAGE{$lang}{txt}, '';
                txt_ $LANGUAGE{$lang}{txt};
                small_ sprintf ' (%d)', scalar $lang{$lang}->@*;
            };
            table_ class => 'releases', sub {
                release_row_ $_, $ropt for $lang{$lang}->@*;
            };
        };
    }

    article_ class => 'vnreleases', sub {
        h1_ 'Releases';
        if(!$v->{releases}->@*) {
            p_ 'We don\'t have any information about releases of this visual novel yet...';
        } else {
            lang_ $_ for @lang;
        }
    }
}


sub staff_cols_ {
    my($lst) = @_;

    # XXX: The staff listing is included in the page 3 times, for 3 different
    # layouts. A better approach to get the same layout is to add the boxes to
    # the HTML once with classes indicating the box position (e.g.
    # "4col-col1-row1 3col-col2-row1" etc) and then using CSS to position the
    # box appropriately. My attempts to do this have failed, however. The
    # layouting can also be done in JS, but that's not my preferred option.

    # Step 1: Get a list of 'boxes'; Each 'box' represents a role with a list of staff entries.
    # @boxes = [ $height, $roleimp, $html ]
    my %roles;
    push $roles{$_->{role}}->@*, $_ for grep $_->{sid}, @$lst;
    my $i=0;
    my @boxes =
        sort { $b->[0] <=> $a->[0] || $a->[1] <=> $b->[1] }
        map [ 2+$roles{$_}->@*, $i++,
            xml_string sub {
                li_ class => 'vnstaff_head', $CREDIT_TYPE{$_};
                li_ sub {
                    a_ href => "/$_->{sid}", tattr $_;
                    small_ $_->{note} if $_->{note};
                } for sort { $a->{title}[1] cmp $b->{title}[1] } $roles{$_}->@*;
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

    div_ class => sprintf('vnstaff-%d', scalar @$_), sub {
        ul_ sub {
            lit_ $_->[2] for $_->[2]->@*;
        } for @$_
    } for @cols;
}


sub staff_ {
    my($v) = @_;
    return if !$v->{staff}->@*;

    my %staff;
    push $staff{ $_->{eid} // '' }->@*, $_ for $v->{staff}->@*;
    my $pref = prefs;

    article_ class => 'vnstaff', id => 'staff', sub {
        h1_ 'Staff';
        if (!$v->{editions}->@*) {
            staff_cols_ $v->{staff};
            return;
        }
        for my $e (undef, $v->{editions}->@*) {
            my $lst = $staff{ $e ? $e->{eid} : '' };
            next if !$lst;
            my $lang = ($e && $e->{lang}) || $v->{olang};
            my $unoff = $e && !$e->{official};
            my $open = ($pref->{staffed_olang} && !$e) || ($pref->{staffed_langs}{$lang} && (!$unoff || $pref->{staffed_unoff}));
            details_ open => $open?'open':undef, sub {
                summary_ sub {
                    abbr_ class => "icon-lang-$e->{lang}", title => $LANGUAGE{$e->{lang}}{txt}, '' if $e && $e->{lang};
                    txt_ 'Original edition' if !$e;
                    txt_ $e->{name} if $e;
                    small_ ' (unofficial)' if $unoff;
                };
                staff_cols_ $lst;
            };
        }
    };
}


sub charsum_ {
    my($v) = @_;

    my $spoil = viewget->{spoilers};
    my $c = tuwf->dbAlli('
        SELECT c.id, c.title, c.gender, v.role
          FROM', charst, 'c
          JOIN (SELECT id, MIN(role) FROM chars_vns WHERE role <> \'appears\' AND spoil <=', \$spoil, 'AND vid =', \$v->{id}, 'GROUP BY id) v(id,role) ON c.id = v.id
         WHERE NOT c.hidden
         ORDER BY v.role, c.name, c.id'
    );
    return if !@$c;
    enrich seiyuu => id => cid => sub { sql('
        SELECT vs.cid, sa.id, sa.title, vs.note
          FROM vn_seiyuu vs
          JOIN', staff_aliast, 'sa ON sa.aid = vs.aid
         WHERE vs.id =', \$v->{id}, 'AND vs.cid IN', $_, '
         ORDER BY sa.sorttitle'
    ) }, $c;

    article_ 'data-mainbox-summarize' => 210, sub {
        p_ class => 'mainopts', sub {
            a_ href => "/$v->{id}/chars#chars", 'Full character list';
        };
        h1_ 'Character summary';
        div_ class => 'charsum_list', sub {
            div_ class => 'charsum_bubble', sub {
                div_ class => 'name', sub {
                    span_ sub {
                        abbr_ class => "icon-gen-$_->{gender}", title => $GENDER{$_->{gender}}, '' if $_->{gender} ne 'unknown';
                        a_ href => "/$_->{id}", tattr $_;
                    };
                    em_ $CHAR_ROLE{$_->{role}}{txt};
                };
                div_ class => 'actor', sub {
                    txt_ 'Voiced by';
                    $_->{seiyuu}->@* > 1 ? br_ : txt_ ' ';
                    join_ \&br_, sub {
                        a_ href => "/$_->{id}", tattr $_;
                        small_ $_->{note} if $_->{note};
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
         SELECT uv.vote, uv.c_private,', sql_totime('uv.vote_date'), 'as date, ', sql_user(), '
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
                span_ sub {
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
                    small_ 'hidden' if $_->{c_private};
                    user_ $_ if !$_->{c_private};
                };
                td_ fmtvote $_->{vote};
                td_ fmtdate $_->{date};
            } for @$recent;
        } if $recent && @$recent;

        clearfloat_;
        div_ sub {
            h3_ 'Ranking';
            p_ sprintf 'Popularity: ranked #%d with a score of %.2f', $rank->{c_pop_rank}, $rank->{c_popularity}/100 if defined $rank->{c_popularity};
            p_ sprintf 'Bayesian rating: ranked #%d with a rating of %.2f', $rank->{c_rat_rank}, $rank->{c_rating}/100;
        } if $v->{c_votecount};
    }

    article_ id => 'stats', sub {
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
    article_ id => 'screenshots', sub {

        p_ class => 'mainopts', sub {
            if($sexp < 0 || $sex[1] || $sex[2]) {
                label_ for => 'scrhide_s0', class => 'fake_link', "Safe ($sex[0])";
                label_ for => 'scrhide_s1', class => 'fake_link', "Suggestive ($sex[1])" if $sex[1];
                label_ for => 'scrhide_s2', class => 'fake_link', "Explicit ($sex[2])" if $sex[2];
            }
            small_ ' | ' if ($sexp < 0 || $sex[1] || $sex[2]) && ($vio[1] || $vio[2]);
            if($vio[1] || $vio[2]) {
                label_ for => 'scrhide_v0', class => 'fake_link', "Tame ($vio[0])";
                label_ for => 'scrhide_v1', class => 'fake_link', "Violent ($vio[1])" if $vio[1];
                label_ for => 'scrhide_v2', class => 'fake_link', "Brutal ($vio[2])" if $vio[2];
            }
        } if $sexp < 0 || $sex[1] || $sex[2] || $vio[1] || $vio[2];

        h1_ 'Screenshots';

        for my $r (grep $rel{$_->{id}}, $v->{releases}->@*) {
            p_ class => 'rel', sub {
                abbr_ class => "icon-lang-$_->{lang}", title => $LANGUAGE{$_->{lang}}{txt}, '' for $r->{titles}->@*;
                platform_ $_ for $r->{platforms}->@*;
                a_ href => "/$r->{id}", tattr $r;
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
        article_ sub {
            h1_ 'Tags';
            p_ 'This VN has no tags assigned to it (yet).';
        };
        return;
    }

    my %tags = map +($_->{id},$_), $v->{tags}->@*;
    my $parents = tuwf->dbAlli("
        WITH RECURSIVE parents (tag, child) AS (
          SELECT tag::vndbid, NULL::vndbid FROM (VALUES", sql_join(',', map sql('(',\$_,')'), keys %tags), ") AS x(tag)
          UNION
          SELECT tp.parent, tp.id FROM tags_parents tp, parents a WHERE a.tag = tp.id AND tp.main
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
        $t->{override} //= min map $tags{$_}{override}//$tags{$_}{spoiler}, $t->{childs}->@* if grep defined($tags{$_}{override}), $t->{childs}->@*;
        $t->{rating} //= sum(map $tags{$_}{rating}, $t->{childs}->@*) / $t->{childs}->@*;
    }
    scores $_ for @roots;

    my $view = viewget;
    my sub rec {
        my($lvl, $t) = @_;
        return if ($t->{override}//$t->{spoiler}) > $view->{spoilers};
        li_ class => "tagvnlist-top", sub {
            h3_ sub { a_ href => "/$t->{id}", $t->{name} }
        } if !$lvl;

        li_ $lvl == 1 ? (class => 'tagvnlist-parent') : $t->{inherited} ? (class => 'tagvnlist-inherited') : (), sub {
            VNWeb::TT::Lib::tagscore_($t->{rating}, $t->{inherited});
            small_ '━━'x($lvl-1).' ' if $lvl > 1;
            a_ href => "/$t->{id}", mkclass(
                    $t->{color} ? ($t->{color}, $t->{color} =~ /standout|grayedout/ ? 1 : 0) : (),
                    lie => $t->{lie} && ($view->{spoilers} > 1 || defined $t->{override}),
                    parent => !$t->{rating}
                ), ($t->{color}//'') =~ /^#/ ? (style => "color: $t->{color}") : (),
                $t->{name};
            spoil_ $t->{spoiler};
        } if $lvl;

        if($t->{childs}) {
            __SUB__->($lvl+1, $_) for sort { $a->{name} cmp $b->{name} } map $tags{$_}, $t->{childs}->@*;
        }
    }

    article_ sub {
        my $max_spoil = max map $_->{lie}?2:$_->{spoiler}, values %tags;
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

    framework_ title => $v->{title}[1], index => !tuwf->capture('rev'), dbobj => $v, hiddenmsg => 1, js => 1, og => og($v),
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

    framework_ title => $v->{title}[1], index => 1, dbobj => $v, hiddenmsg => 1,
    sub {
        infobox_ $v, 1;
        tabs_ $v, 'tags';
        tags_ $v;
    };
};

1;
