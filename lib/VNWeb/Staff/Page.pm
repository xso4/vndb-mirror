package VNWeb::Staff::Page;

use VNWeb::Prelude;
use VNWeb::ULists::Lib;


sub enrich_item {
    my($s) = @_;

    # Add a 'main' flag and title field to each alias
    for ($s->{alias}->@*) {
        $_->{main} = $s->{main} == $_->{aid};
        $_->{title} = titleprefs_swap $s->{lang}, $_->{name}, $_->{latin};
    }
}


sub _rev_ {
    my($s) = @_;
    my %aid;
    revision_ $s, \&enrich_item,
        [ alias  => 'Names', fmt => sub {
            my $num = ($aid{$_->{aid}} ||= keys %aid);
            strong_ "$num: ";
            txt_ $_->{name};
            txt_ " ($_->{latin})" if $_->{latin};
            small_ ' (primary)' if $_->{main};
        } ],
        [ gender => 'Gender',     fmt => \%STAFF_GENDER ],
        [ lang   => 'Language',   fmt => \%LANGUAGE ],
        [ description => 'Description' ],
        $VNDB::ExtLinks::REVISION
}


sub _infotable_ {
    my($main, $s) = @_;
    table_ class => 'stripe', sub {
        thead_ sub { tr_ sub {
            td_ colspan => 2, sub {
                debug_ $s;
                span_ style => 'margin-right: 10px', tlang($main->{title}[0], $main->{title}[1]), $main->{title}[1];
                small_ style => 'margin-right: 10px', tlang($main->{title}[2], $main->{title}[3]), $main->{title}[3] if $main->{title}[1] ne $main->{title}[3];
                abbr_ class => "icon-char-$s->{gender} charsex-w", title => $STAFF_GENDER{$s->{gender}}, '' if $s->{gender};
            }
        } };

        tr_ sub {
            td_ class => 'key', 'Language';
            td_ $LANGUAGE{$s->{lang}}{txt};
        };

        my @alias = sort { ($a->{latin}//$a->{name}) cmp ($b->{latin}//$b->{name}) } grep !$_->{main}, $s->{alias}->@*;
        tr_ sub {
            td_ @alias == 1 ? 'Alias' : 'Aliases';
            td_ sub {
                table_ class => 'aliases', sub {
                    tr_ class => 'nostripe', sub {
                        td_ class => 'key', $_->{latin} ? () : (colspan => 2), tlang($s->{lang}, $_->{name}), $_->{name};
                        td_ tlang($s->{lang}, $_->{latin}), $_->{latin} if $_->{latin};
                    } for @alias;
                };
            };
        } if @alias;

        tr_ sub {
            td_ class => 'key', 'Links';
            td_ sub {
                join_ \&br_, sub { a_ href => $_->{url2}, $_->{label} }, $s->{vislinks}->@*;
            };
        } if $s->{vislinks}->@*;
    };
}


sub _roles_ {
    my($s) = @_;
    my %alias = map +($_->{aid}, $_), $s->{alias}->@*;

    my $roles = tuwf->dbAlli('
        SELECT v.id, vs.aid, vs.role, vs.note, ve.name, ve.official, ve.lang, v.c_released, v.title
          FROM vn_staff vs
          JOIN', vnt, 'v ON v.id = vs.id
          LEFT JOIN vn_editions ve ON ve.id = vs.id AND ve.eid = vs.eid
         WHERE vs.aid IN', [ keys %alias ], '
           AND NOT v.hidden
         ORDER BY v.c_released ASC, v.sorttitle ASC, ve.lang NULLS FIRST, ve.name NULLS FIRST, vs.role ASC
    ');
    return if !@$roles;
    enrich_ulists_widget $roles;

    nav_ sub {
        h1_ sprintf 'Credits (%d)', scalar @$roles;
    };
    article_ class => 'browse staffroles', sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc_ulist', '' if auth;
                td_ class => 'tc1', 'Title';
                td_ class => 'tc2', 'Released';
                td_ class => 'tc3', 'Role';
                td_ class => 'tc4', 'As';
                td_ class => 'tc5', 'Note';
            }};
            my %vns;
            tr_ sub {
                my($v, $a) = ($_, $alias{$_->{aid}});
                td_ class => 'tc_ulist', sub { ulists_widget_ $v if !$vns{$v->{id}}++ } if auth;
                td_ class => 'tc1', sub {
                    a_ href => "/$v->{id}", tattr $v;
                    lit_ ' ' if $v->{name};
                    abbr_ class => "icon-lang-$v->{lang}", title => $LANGUAGE{$v->{lang}}{txt}, '' if $v->{lang};
                    txt_ $v->{name} if $v->{name} && $v->{official};
                    small_ $v->{name} if $v->{name} && !$v->{official};
                };
                td_ class => 'tc2', sub { rdate_ $v->{c_released} };
                td_ class => 'tc3', $CREDIT_TYPE{$v->{role}};
                td_ class => 'tc4', tattr $a;
                td_ class => 'tc5', $v->{note};
            } for @$roles;
        };
    };
}


sub _cast_ {
    my($s) = @_;
    my %alias = map +($_->{aid}, $_), $s->{alias}->@*;

    my $cast = [ grep defined $_->{spoil}, tuwf->dbAlli('
        SELECT vs.aid, v.id, v.c_released, v.title, c.id AS cid, c.title AS c_title, vs.note,
               (SELECT MIN(cv.spoil) FROM chars_vns cv WHERE cv.id = c.id AND cv.vid = v.id) AS spoil
          FROM vn_seiyuu vs
          JOIN', vnt, 'v ON v.id = vs.id
          JOIN', charst, 'c ON c.id = vs.cid
         WHERE vs.aid IN', [ keys %alias ], '
           AND NOT v.hidden
           AND NOT c.hidden
         ORDER BY v.c_released ASC, v.sorttitle ASC
    ')->@* ];
    return if !@$cast;
    enrich_ulists_widget $cast;

    my $spoilers = viewget->{spoilers};
    my $max_spoil = max(map $_->{spoil}, @$cast);

    nav_ sub {
        h1_ sprintf 'Voiced characters (%d)', scalar @$cast;
        menu_ sub {
            li_ class => $spoilers == 0 ? 'tabselected' : undef, sub { a_ href => '?view='.viewset(spoilers => 0), 'hide spoilers' };
            li_ class => $spoilers == 1 ? 'tabselected' : undef, sub { a_ href => '?view='.viewset(spoilers => 1), 'minor spoilers' };
            li_ class => $spoilers == 2 ? 'tabselected' : undef, sub { a_ href => '?view='.viewset(spoilers => 2), 'spoil me!' } if $max_spoil == 2;
        } if $max_spoil;
    };
    article_ class => "browse staffroles", sub {
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub {
                td_ class => 'tc_ulist', '' if auth;
                td_ class => 'tc1', sub { txt_ 'Title'; debug_ $cast };
                td_ class => 'tc2', 'Released';
                td_ class => 'tc3', 'Cast';
                td_ class => 'tc4', 'As';
                td_ class => 'tc5', 'Note';
            }};
            my %vns;
            tr_ sub {
                my($v, $a) = ($_, $alias{$_->{aid}});
                td_ class => 'tc_ulist', sub { ulists_widget_ $v if !$vns{$v->{id}}++ } if auth;
                td_ class => 'tc1', sub {
                    a_ href => "/$v->{id}", tattr $v;
                };
                td_ class => 'tc2', sub { rdate_ $v->{c_released} };
                td_ class => 'tc3', sub {
                    a_ href => "/$v->{cid}", tattr $v->{c_title};
                    spoil_ $_->{spoil};
                };
                td_ class => 'tc4', tattr $a;
                td_ class => 'tc5', $v->{note};
            } for grep $_->{spoil} <= $spoilers, @$cast;
        };
    };
}


TUWF::get qr{/$RE{srev}} => sub {
    my $s = db_entry tuwf->captures('id', 'rev');
    return tuwf->resNotFound if !$s;

    enrich_item $s;
    enrich_vislinks s => 0, $s;
    my($main) = grep $_->{aid} == $s->{main}, $s->{alias}->@*;

    framework_ title => $main->{title}[1], index => !tuwf->capture('rev'), dbobj => $s, hiddenmsg => 1,
        og => {
            description => bb_format $s->{description}, text => 1
        },
    sub {
        _rev_ $s if tuwf->capture('rev');
        article_ class => 'staffpage', sub {
            itemmsg_ $s;
            h1_ tlang(@{$main->{title}}[0,1]), $main->{title}[1];
            h2_ class => 'alttitle', tlang(@{$main->{title}}[2,3]), $main->{title}[3] if $main->{title}[3] && $main->{title}[3] ne $main->{title}[1];
            _infotable_ $main, $s;
            div_ class => 'description', sub { lit_ bb_format $s->{description} };
        };

        _roles_ $s;
        _cast_ $s;
    };
};

1;
