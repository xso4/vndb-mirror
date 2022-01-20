package VNWeb::Releases::Page;

use VNWeb::Prelude;


sub enrich_item {
    my($r) = @_;

    enrich_merge pid => 'SELECT id AS pid, name, original FROM producers WHERE id IN', $r->{producers};
    enrich_merge vid => 'SELECT id AS vid, title, alttitle FROM vnt WHERE id IN', $r->{vn};

    $r->{lang}      = [ sort { ($a->{mtl}?1:0) <=> ($b->{mtl}?1:0) || $a->{lang} cmp $b->{lang} } $r->{lang}->@* ];
    $r->{platforms} = [ sort map $_->{platform}, $r->{platforms}->@* ];
    $r->{vn}        = [ sort { $a->{title}  cmp $b->{title}  || idcmp($a->{vid}, $b->{vid}) } $r->{vn}->@*        ];
    $r->{producers} = [ sort { $a->{name}   cmp $b->{name}   || idcmp($a->{pid}, $b->{pid}) } $r->{producers}->@* ];
    $r->{media}     = [ sort { $a->{medium} cmp $b->{medium} || $a->{qty} <=> $b->{qty} } $r->{media}->@*     ];

    $r->{resolution} = resolution $r;
}


sub _rev_ {
    my($r) = @_;
    revision_ $r, \&enrich_item,
        [ vn         => 'Relations',       fmt => sub {
            abbr_ class => "icons rt$_->{rtype}", title => $_->{rtype}, ' ';
            a_ href => "/$_->{vid}", title => $_->{alttitle}||$_->{title}, $_->{title};
            txt_ " ($_->{rtype})" if $_->{rtype} ne 'complete';
        } ],
        [ official   => 'Official',        fmt => 'bool' ],
        [ patch      => 'Patch',           fmt => 'bool' ],
        [ freeware   => 'Freeware',        fmt => 'bool' ],
        [ doujin     => 'Doujin',          fmt => 'bool' ],
        [ uncensored => 'Uncensored',      fmt => 'bool' ],
        [ title      => 'Title (Romaji)' ],
        [ original   => 'Original title' ],
        [ gtin       => 'JAN/EAN/UPC',     empty => 0 ],
        [ catalog    => 'Catalog number' ],
        [ lang       => 'Languages',       fmt => sub { txt_ $LANGUAGE{$_->{lang}}; txt_ ' (machine translation)' if $_->{mtl} } ],
        [ released   => 'Release date',    fmt => sub { rdate_ $_ } ],
        [ minage     => 'Age rating',      fmt => sub { txt_ minage $_ } ],
        [ notes      => 'Notes' ],
        [ platforms  => 'Platforms',       fmt => \%PLATFORM ],
        [ media      => 'Media',           fmt => sub { txt_ fmtmedia $_->{medium}, $_->{qty}; } ],
        [ resolution => 'Resolution'     ],
        [ voiced     => 'Voiced',          fmt => \%VOICED ],
        [ ani_story  => 'Story animation', fmt => \%ANIMATED ],
        [ ani_ero    => 'Ero animation',   fmt => \%ANIMATED ],
        [ engine     => 'Engine' ],
        [ producers  => 'Producers',       fmt => sub {
            a_ href => "/$_->{pid}", title => $_->{original}||$_->{name}, $_->{name};
            txt_ ' (';
            txt_ join ', ', $_->{developer} ? 'developer' : (), $_->{publisher} ? 'publisher' : ();
            txt_ ')';
        } ],
        revision_extlinks 'r'
}


sub _infotable_ {
    my($r) = @_;

    table_ class => 'stripe', sub {
        tr_ sub {
            td_ class => 'key', 'Relation';
            td_ sub {
                join_ \&br_, sub {
                    abbr_ class => "icons rt$_->{rtype}", title => $_->{rtype}, ' ';
                    a_ href => "/$_->{vid}", title => $_->{alttitle}||$_->{title}, $_->{title};
                    txt_ " ($_->{rtype})" if $_->{rtype} ne 'complete';
                }, $r->{vn}->@*
            }
        };

        tr_ sub {
            td_ 'Title';
            td_ $r->{title};
        };

        tr_ sub {
            td_ 'Original title';
            td_ lang_attr($r->{lang}), $r->{original};
        } if $r->{original};

        tr_ sub {
            td_ 'Type';
            td_ !$r->{official} && $r->{patch} ? 'Unofficial patch' :
                !$r->{official} ? 'Unofficial' : 'Patch';
        } if !$r->{official} || $r->{patch};

        tr_ sub {
            td_ 'Language';
            td_ sub {
                join_ \&br_, sub {
                    abbr_ class => "icons lang $_->{lang}", title => $LANGUAGE{$_->{lang}}, ' ';
                    txt_ ' ';
                    if($_->{mtl}) {
                        b_ class => 'grayedout', $LANGUAGE{$_->{lang}};
                        txt_ ' (machine translation)';
                    } else {
                        txt_ $LANGUAGE{$_->{lang}};
                    }
                }, $r->{lang}->@*;
            }
        };

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

        tr_ sub {
            td_ 'Animation';
            td_ sub {
                join_ \&br_, sub { txt_ $_ },
                    $r->{ani_story} ? "Story: $ANIMATED{$r->{ani_story}}{txt}" : (),
                    $r->{ani_ero}   ? "Ero scenes: $ANIMATED{$r->{ani_ero}}{txt}" : ();
            }
        } if $r->{ani_story} || $r->{ani_ero};

        tr_ sub {
            td_ 'Engine';
            td_ sub {
                a_ href => '/r?f='.tuwf->compile({advsearch => 'r'})->validate(['engine', '=', $r->{engine}])->data->query_encode, $r->{engine};
            }
        } if length $r->{engine};

        tr_ sub {
            td_ 'Released';
            td_ sub { rdate_ $r->{released} };
        };

        tr_ sub {
            td_ 'Age rating';
            td_ minage $r->{minage};
        } if defined $r->{minage};

        tr_ sub {
            td_ 'Censoring';
            td_ $r->{uncensored} ? 'No optical censoring (like mosaics)' : 'Includes optical censoring (e.g. mosaics)';
        } if defined $r->{uncensored};

        for my $t (qw|developer publisher|) {
            my @prod = grep $_->{$t}, @{$r->{producers}};
            tr_ sub {
                td_ ucfirst($t).(@prod == 1 ? '' : 's');
                td_ sub {
                    join_ \&br_, sub {
                        a_ href => "/$_->{pid}", title => $_->{original}||$_->{name}, $_->{name};
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
                join_ ', ', sub { a_ href => $_->[1], $_->[0] }, $r->{extlinks}->@*;
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


TUWF::get qr{/$RE{rrev}} => sub {
    my $r = db_entry tuwf->captures('id','rev');
    return tuwf->resNotFound if !$r;

    enrich_item $r;
    enrich_extlinks r => $r;

    framework_ title => $r->{title}, index => !tuwf->capture('rev'), dbobj => $r, hiddenmsg => 1,
        og => {
            description => bb_format $r->{notes}, text => 1
        },
    sub {
        _rev_ $r if tuwf->capture('rev');
        div_ class => 'mainbox release', sub {
            itemmsg_ $r;
            h1_ sub { txt_ $r->{title}; debug_ $r };
            h2_ class => 'alttitle', lang_attr($r->{lang}), $r->{original} if length $r->{original};
            _infotable_ $r;
            div_ class => 'description', sub { lit_ bb_format $r->{notes} } if $r->{notes};
        };
    };
};

1;
