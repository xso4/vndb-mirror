package VNWeb::Releases::Page;

use VNWeb::Prelude;
use TUWF 'uri_escape';
use VNWeb::Images::Lib;
use VNWeb::Releases::Lib;


sub enrich_item {
    my($r) = @_;

    enrich_merge pid => sql('SELECT id AS pid, title, sorttitle FROM', producerst, 'p WHERE id IN'), $r->{producers};
    enrich_merge vid => sql('SELECT id AS vid, title, sorttitle FROM', vnt, 'v WHERE id IN'), $r->{vn};
    enrich_merge drm => sql('SELECT id AS drm, name,', sql_join(',', keys %DRM_PROPERTY), 'FROM drm WHERE id IN'), $r->{drm};
    enrich_image_obj img => $r->{images};

    $r->{titles}    = [ sort { ($b->{lang} eq $r->{olang}) cmp ($a->{lang} eq $r->{olang}) || ($a->{mtl}?1:0) <=> ($b->{mtl}?1:0) || $a->{lang} cmp $b->{lang} } $r->{titles}->@* ];
    $r->{platforms} = [ sort map $_->{platform}, $r->{platforms}->@* ];
    $r->{vn}        = [ sort { $a->{sorttitle} cmp $b->{sorttitle} || idcmp($a->{vid}, $b->{vid}) } $r->{vn}->@*        ];
    $r->{producers} = [ sort { $a->{sorttitle} cmp $b->{sorttitle} || idcmp($a->{pid}, $b->{pid}) } $r->{producers}->@* ];
    $r->{media}     = [ sort { $a->{medium} cmp $b->{medium} || $a->{qty} <=> $b->{qty} } $r->{media}->@*     ];
    $r->{drm}       = [ sort { !$a->{drm} || !$b->{drm} ? $b->{drm} <=> $a->{drm} : $a->{name} cmp $b->{name} } $r->{drm}->@* ];
    # TODO: Ensure 'images' has a stable order

    $r->{resolution} = resolution $r;
}


sub _rev_ {
    my($r) = @_;
    # The old ani_* fields are automatically inferred from the new ani_* fields
    # for edits made after the fields were introduced. Hide the old fields for
    # such revisions to remove some clutter.
    my $newani = $r->{chid} > 1110896;
    revision_ $r, \&enrich_item,
        [ vn         => 'Relations',       fmt => sub {
            abbr_ class => "icon-rt$_->{rtype}", title => $_->{rtype}, ' ';
            a_ href => "/$_->{vid}", tattr $_;
            txt_ " ($_->{rtype})" if $_->{rtype} ne 'complete';
        } ],
        [ official   => 'Official',        fmt => 'bool' ],
        [ patch      => 'Patch',           fmt => 'bool' ],
        [ freeware   => 'Freeware',        fmt => 'bool' ],
        [ has_ero    => 'Has ero',         fmt => 'bool' ],
        [ doujin     => 'Doujin',          fmt => 'bool' ],
        [ uncensored => 'Uncensored',      fmt => 'bool' ],
        [ gtin       => 'JAN/EAN/UPC/ISBN',empty => 0 ],
        [ catalog    => 'Catalog number' ],
        [ titles     => 'Languages',       txt => sub {
            '['.$_->{lang}.($_->{mtl} ? ' machine translation' : '').'] '.($_->{title}//'').(length $_->{latin} ? " / $_->{latin}" : '')
        }],
        [ olang      => 'Main title',      fmt => \%LANGUAGE ],
        [ released   => 'Release date',    fmt => sub { rdate_ $_ } ],
        [ minage     => 'Age rating',      fmt => sub { txt_ minage $_ } ],
        [ notes      => 'Notes' ],
        [ platforms  => 'Platforms',       fmt => \%PLATFORM ],
        [ media      => 'Media',           fmt => sub { txt_ fmtmedia $_->{medium}, $_->{qty}; } ],
        [ resolution => 'Resolution'     ],
        [ voiced     => 'Voiced',          fmt => \%VOICED ],
        $newani ? () :
        [ ani_story    => 'Story animation',     fmt => \%ANIMATED ],
        [ ani_story_sp => 'Story animation/sprites',fmt => sub { txt_ fmtanimation $_, 'sprites' } ],
        [ ani_story_cg => 'Story animation/cg',  fmt => sub { txt_ fmtanimation $_, 'CGs' } ],
        [ ani_cutscene => 'Cutscene animation',  fmt => sub { txt_ fmtanimation $_, 'cutscenes' } ],
        $newani ? () :
        [ ani_ero    => 'Ero animation',       fmt => \%ANIMATED ],
        [ ani_ero_sp => 'Ero animation/sprites',fmt=> sub { txt_ fmtanimation $_, 'sprites' } ],
        [ ani_ero_cg => 'Ero animation/cg',    fmt => sub { txt_ fmtanimation $_, 'CGs' } ],
        [ ani_face   => 'Lip/eye animation',   fmt => 'bool' ],
        [ ani_bg     => 'Background effects',  fmt => 'bool' ],
        [ engine     => 'Engine' ],
        [ producers  => 'Producers',       fmt => sub {
            a_ href => "/$_->{pid}", tattr $_;
            txt_ ' (';
            txt_ join ', ', $_->{developer} ? 'developer' : (), $_->{publisher} ? 'publisher' : ();
            txt_ ')';
        } ],
        [ drm        => 'DRM', fmt => sub {
            a_ href => '/r/drm?s='.uri_escape($_->{name}), $_->{name};
            txt_ " ($_->{notes})" if length $_->{notes};
        } ],
        [ images     => 'Images', fmt => sub {
            my $rev = $_[0]{chid} == $r->{chid} ? 'new' : 'old';
            a_ imgiv($_->{img}, $rev), $_->{img}{id};
            txt_ " [$_->{img}{width}x$_->{img}{height}; ";
            a_ href => "/$_->{img}{id}", image_flagging_display $_->{img} if auth;
            span_ image_flagging_display $_->{img} if !auth;
            txt_ "] $RELEASE_IMAGE_TYPE{$_->{itype}}{txt}";
            if ($_->{vid}) {
                small_ ' [';
                a_ href => "/$_->{vid}", $_->{vid};
                small_ ']';
            }
        } ],
        revision_extlinks 'r'
}


sub _infotable_animation_ {
    my($r) = @_;
    state @fields = qw|ani_story_sp ani_story_cg ani_cutscene ani_ero_sp ani_ero_cg ani_bg ani_face|;

    return if !$r->{ani_story} && !$r->{ani_ero};

    my sub txtc {
        my($bool, $txt) = @_;
        +(sub { $bool ? txt_ $txt : small_ $txt })
    }

    my sub sect {
        my($val, $lbl) = @_;
        defined $val ? txtc $val > 2, fmtanimation $val, $lbl : ();
    }

    my @story = !$r->{ani_story} ? () :
        defined $r->{ani_story_sp} || defined $r->{ani_story_cg} || defined $r->{ani_cutscene} || defined $r->{ani_bg} || defined $r->{ani_face} ? (
            defined $r->{ani_story_sp} ? sect $r->{ani_story_sp}, 'sprites' : (),
            defined $r->{ani_story_cg} ? sect $r->{ani_story_cg}, 'CGs' : (),
            defined $r->{ani_cutscene} ? sect $r->{ani_cutscene}, 'cutscenes' : (),
        ) : txtc $r->{ani_story} > 1, $ANIMATED{$r->{ani_story}}{txt};

    my @ero = !$r->{ani_ero} ? () :
        defined $r->{ani_ero_sp} || defined $r->{ani_ero_cg} ? (
            defined $r->{ani_ero_sp} ? sect $r->{ani_ero_sp}, 'sprites' : (),
            defined $r->{ani_ero_cg} ? sect $r->{ani_ero_cg}, 'CGs' : (),
        ) : txtc $r->{ani_ero} > 1, $ANIMATED{$r->{ani_ero}}{txt};

    tr_ sub {
        td_ 'Animation';
        td_ sub {
            dl_ sub {
                if(@story) {
                    dt_ 'Story scenes';
                    dd_ sub { join_ \&br_, sub { $_->() }, @story };
                }
                if(@ero) {
                    dt_ 'Erotic scenes';
                    dd_ sub { join_ \&br_, sub { $_->() }, @ero };
                }
            } if @story || @ero;
            join_ \&br_, sub { $_->() },
                defined $r->{ani_bg}   ? (txtc $r->{ani_bg},   $r->{ani_bg} ? 'Animated background effects' : 'No background effects') : (),
                defined $r->{ani_face} ? (txtc $r->{ani_face}, $r->{ani_face} ? 'Lip and/or eye movement' : 'No facial animations') : ();
        };
    };
}


sub _infotable_ {
    my($r) = @_;

    table_ class => 'stripe', sub {
        tr_ sub {
            td_ class => 'key', 'Relation';
            td_ sub {
                join_ \&br_, sub {
                    abbr_ class => "icon-rt$_->{rtype}", title => $_->{rtype}, ' ';
                    a_ href => "/$_->{vid}", tattr $_;
                    txt_ " ($_->{rtype})" if $_->{rtype} ne 'complete';
                }, $r->{vn}->@*
            }
        };

        tr_ class => 'titles', sub {
            td_ $r->{titles}->@* == 1 ? 'Title' : 'Titles';
            td_ sub {
                table_ sub {
                    my($olang) = grep $_->{lang} eq $r->{olang}, $r->{titles}->@*;
                    tr_ class => 'nostripe title', sub {
                        td_ style => 'white-space: nowrap', sub {
                            abbr_ class => "icon-lang-$_->{lang}", title => $LANGUAGE{$_->{lang}}{txt}, '';
                        };
                        td_ sub {
                            my $title = $_->{title}//$olang->{title};
                            span_ tlang($_->{lang}, $title), $title;
                            small_ ' (machine translation)' if $_->{mtl};
                            my $latin = defined $_->{title} ? $_->{latin} : $olang->{latin};
                            if(defined $latin) {
                                br_;
                                txt_ $latin;
                            }
                        }
                    } for $r->{titles}->@*;
                };
            };
        };

        tr_ sub {
            td_ 'Type';
            td_ !$r->{official} && $r->{patch} ? 'Unofficial patch' :
                !$r->{official} ? 'Unofficial' : 'Patch';
        } if !$r->{official} || $r->{patch};

        tr_ sub {
            td_ 'Publication';
            td_ $r->{freeware} ? 'Freeware' : 'Non-free';
        };

        tr_ sub {
            td_ 'Platform'.($r->{platforms}->@* == 1 ? '' : 's');
            td_ sub {
                join_ \&br_, sub {
                    platform_ $_;
                    txt_ ' '.$PLATFORM{$_};
                }, $r->{platforms}->@*;
            }
        } if $r->{platforms}->@*;

        tr_ sub {
            td_ $r->{media}->@* == 1 ? 'Medium' : 'Media';
            td_ sub {
                join_ \&br_, sub { txt_ fmtmedia $_->{medium}, $_->{qty} }, $r->{media}->@*;
            }
        } if $r->{media}->@*;

        tr_ sub {
            td_ 'Resolution';
            td_ resolution $r;
        } if $r->{reso_y};

        tr_ sub {
            td_ 'Voiced';
            td_ $VOICED{$r->{voiced}}{txt};
        } if $r->{voiced};

        _infotable_animation_ $r;

        tr_ sub {
            td_ 'Engine';
            td_ sub {
                a_ href => '/r?f='.tuwf->compile({advsearch => 'r'})->validate(['engine', '=', $r->{engine}])->data->query_encode, $r->{engine};
            }
        } if length $r->{engine};

        tr_ sub {
            td_ 'DRM';
            td_ sub { join_ \&br_, sub {
                my $d = $_;
                my @prop = grep $d->{$_}, keys %DRM_PROPERTY;
                abbr_ class => "icon-drm-$_", title => $DRM_PROPERTY{$_}, '' for @prop;
                abbr_ class => 'icon-drm-free', title => 'DRM-free', '' if !@prop;
                a_ href => '/r/drm?s='.uri_escape($d->{name}), $d->{name};
                lit_ ' ('.bb_format($d->{notes}, inline => 1).')' if length $d->{notes};
            }, $r->{drm}->@* };
        } if $r->{drm}->@*;

        tr_ sub {
            td_ 'Released';
            td_ sub { rdate_ $r->{released} };
        };

        tr_ sub {
            td_ 'Age rating';
            td_ minage $r->{minage};
        } if defined $r->{minage};

        tr_ sub {
            td_ 'Erotic content';
            td_ $r->{uncensored} ? 'Contains uncensored erotic scenes' : defined $r->{uncensored} ? 'Contains erotic scenes with optical censoring' : 'Contains erotic scenes',
        } if $r->{has_ero};

        for my $t (qw|developer publisher|) {
            my @prod = grep $_->{$t}, @{$r->{producers}};
            tr_ sub {
                td_ ucfirst($t).(@prod == 1 ? '' : 's');
                td_ sub {
                    join_ \&br_, sub {
                        a_ href => "/$_->{pid}", tattr $_;
                    }, @prod
                }
            } if @prod;
        }

        tr_ sub {
            td_ gtintype($r->{gtin}) || 'GTIN';
            td_ $r->{gtin};
        } if $r->{gtin};

        tr_ sub {
            td_ 'Catalog no.';
            td_ $r->{catalog};
        } if $r->{catalog};

        tr_ sub {
            td_ 'Links';
            td_ sub {
                if ($r->{patch} || $r->{official} || !grep $_->{mtl}, $r->{titles}->@*) {
                    join_ ', ', sub { a_ href => $_->{url2}, $_->{label} }, $r->{extlinks}->@*;
                } else {
                    small_ 'piracy link hidden';
                }
            }
        } if $r->{extlinks}->@*;

        tr_ sub {
            td_ 'User options';
            td_ sub {
                div_ class => 'elm_dd_input', style => 'width: 150px', sub {
                    my $d = tuwf->dbVali('SELECT status FROM rlists WHERE', { rid => $r->{id}, uid => auth->uid });
                    elm_ 'UList.ReleaseEdit', $VNWeb::ULists::Elm::RLIST_STATUS, { rid => $r->{id}, uid => auth->uid, status => $d, empty => 'not on your list' };
                }
            };
        } if auth;
    }
}


sub _images_ {
    my($r) = @_;

    div_ class => 'relimg', sub {
        div_ sub {
            h3_ sub {
                if ($_->{vid}) {
                    small_ '[';
                    a_ href => "/$_->{vid}", $_->{vid};
                    small_ '] ';
                }
                txt_ $RELEASE_IMAGE_TYPE{$_->{itype}}{txt};
            };
            image_ $_->{img}, thumb => 1;
        } for sort { $RELEASE_IMAGE_TYPE{$a->{itype}}{ord} <=> $RELEASE_IMAGE_TYPE{$b->{itype}}{ord} } $r->{images}->@*;
    };
}


TUWF::get qr{/$RE{rrev}} => sub {
    my $r = db_entry tuwf->captures('id','rev');
    return tuwf->resNotFound if !$r;

    $r->{title} = titleprefs_obj $r->{olang}, $r->{titles};
    enrich_item $r;
    enrich_extlinks r => 0, $r;

    framework_ title => $r->{title}[1], index => !tuwf->capture('rev'), dbobj => $r, hiddenmsg => 1, js => 1,
        og => {
            description => bb_format $r->{notes}, text => 1
        },
    sub {
        _rev_ $r if tuwf->capture('rev');
        article_ class => 'release', sub {
            itemmsg_ $r;
            h1_ tlang($r->{title}[0], $r->{title}[1]), $r->{title}[1];
            h2_ class => 'alttitle', tlang(@{$r->{title}}[2,3]), $r->{title}[3] if $r->{title}[3] && $r->{title}[3] ne $r->{title}[1];
            _infotable_ $r;
            div_ class => 'description', sub { lit_ bb_format $r->{notes} } if $r->{notes};
            _images_ $r if $r->{images}->@*;
        };
    };
};

1;
