package VNWeb::Chars::Page;

use VNWeb::Prelude;
use VNWeb::Images::Lib qw/image_ enrich_image_obj/;


sub enrich_seiyuu {
    my($vid, @chars) = @_;
    enrich seiyuu => id => cid => sub { sql '
        SELECT DISTINCT vs.cid, sa.id, sa.title, sa.sorttitle, vs.note
          FROM vn_seiyuu vs
          ', $vid ? () : ('JOIN vn v ON v.id = vs.id'), '
          JOIN', staff_aliast, 'sa ON sa.aid = vs.aid
         WHERE ', $vid ? ('vs.id =', \$vid) : ('NOT v.hidden'), 'AND vs.cid IN', $_, '
         ORDER BY sa.sorttitle'
    }, @chars;
}

sub sql_trait_overrides {
    sql '(
        WITH RECURSIVE trait_overrides (tid, spoil, color, childs, lvl) AS (
          SELECT tid, spoil, color, childs, 0 FROM users_prefs_traits WHERE id =', \auth->uid, '
           UNION ALL
          SELECT tp.id, x.spoil, x.color, true, lvl+1
            FROM trait_overrides x
            JOIN traits_parents tp ON tp.parent = x.tid
           WHERE x.childs
        ) SELECT DISTINCT ON(tid) tid, spoil, color FROM trait_overrides ORDER BY tid, lvl
    )';
}

sub enrich_item {
    my($c) = @_;

    enrich_image_obj image => $c;

    # Even with trait overrides, we'll want to see the raw data in revision diffs,
    # so fetch the raw spoil as a separate column and do filtering/processing later.
    enrich_merge tid => sub { sql '
      SELECT t.id AS tid, t.name, t.hidden, t.locked, t.applicable, t.sexual, x.spoil AS override, x.color
           , coalesce(g.id, t.id) AS group, coalesce(g.name, t.name) AS groupname, coalesce(g.gorder,0) AS order
        FROM traits t
        LEFT JOIN traits g ON t.gid = g.id
        LEFT JOIN', sql_trait_overrides(), 'x ON x.tid = t.id
       WHERE t.id IN', $_
    }, $c->{traits};

    $c->{traits} = [ sort { $a->{order} <=> $b->{order} || $a->{groupname} cmp $b->{groupname} || $a->{name} cmp $b->{name} } grep length $_->{name}, $c->{traits}->@* ];

    $c->{quotes} = tuwf->dbAlli('
        SELECT q.vid, q.id, q.score, q.quote,', sql_totime('q.added'), 'AS added, q.addedby
          FROM quotes q
         WHERE NOT q.hidden AND vid IN', [map $_->{vid}, $c->{vns}->@*], 'AND q.cid =', \$c->{id}, '
         ORDER BY q.score DESC, q.quote
    ');
    enrich_merge id => sql('SELECT id, vote FROM quotes_votes WHERE uid =', \auth->uid, 'AND id IN'), $c->{quotes} if auth;

    $c->{vns} = [ grep length $_->{title}, $c->{vns}->@* ];
}


# Fetch multiple character entries with a format suitable for chartable_()
# Also used by Chars::VNTab.
sub fetch_chars {
    my($vid, $where) = @_;
    my $l = tuwf->dbAlli('
        SELECT id, title, alias, description, sex, spoil_sex, gender, spoil_gender, birthday
             , s_bust, s_waist, s_hip, height, weight, bloodt, cup_size, age, image
          FROM', charst, 'c WHERE NOT hidden AND (', $where, ')
         ORDER BY sorttitle
    ');

    enrich vns => id => id => sub { sql '
        SELECT cv.id, cv.vid, cv.rid, cv.spoil, cv.role, v.title, r.title AS rtitle
          FROM chars_vns cv
          JOIN', vnt, 'v ON v.id = cv.vid
          LEFT JOIN', releasest, 'r ON r.id = cv.rid
         WHERE cv.id IN', $_, $vid ? ('AND cv.vid =', \$vid) : (), '
         ORDER BY v.c_released, r.released, v.sorttitle, cv.vid, cv.rid NULLS LAST'
    }, $l;

    enrich traits => id => id => sub { sql '
        SELECT ct.id, ct.tid, ct.spoil, x.spoil AS override, x.color, ct.lie, t.name, t.hidden, t.locked, t.sexual
             , coalesce(g.id, t.id) AS group, coalesce(g.name, t.name) AS groupname, coalesce(g.gorder,0) AS order
          FROM chars_traits ct
          JOIN traits t ON t.id = ct.tid
          LEFT JOIN traits g ON t.gid = g.id
          LEFT JOIN', sql_trait_overrides(), 'x ON x.tid = ct.tid
         WHERE x.spoil IS DISTINCT FROM 1+1+1 AND ct.id IN', $_, '
         ORDER BY g.gorder NULLS FIRST, coalesce(g.name, t.name), t.name'
    }, $l;

    enrich_seiyuu $vid, $l;
    enrich_image_obj image => $l;
    $l
}


sub _rev_ {
    my($c) = @_;
    revision_ $c, \&enrich_item,
        [ name       => 'Name'           ],
        [ latin      => 'Name (latin)'   ],
        [ alias      => 'Aliases'        ],
        [ description=> 'Description'    ],
        [ sex        => 'Sex',           fmt => \%CHAR_SEX ],
        [ spoil_sex  => 'Sex (spoiler)', empty => undef, fmt => \%CHAR_SEX ],
        [ gender     => 'Gender identity', empty => undef, fmt => \%CHAR_GENDER ],
        [ spoil_gender=>'Gender (spoiler)',empty => undef, fmt => \%CHAR_GENDER ],
        [ birthday   => 'Birthday',      empty => 0, fmt => sub { txt_ fmtbirthday $_ } ],
        [ s_bust     => 'Bust',          empty => 0 ],
        [ s_waist    => 'Waist',         empty => 0 ],
        [ s_hip      => 'Hips',          empty => 0 ],
        [ height     => 'Height',        empty => 0 ],
        [ weight     => 'Weight',        ],
        [ bloodt     => 'Blood type',    fmt => \%BLOOD_TYPE ],
        [ cup_size   => 'Cup size',      fmt => \%CUP_SIZE ],
        [ age        => 'Age',           ],
        [ main       => 'Instance of',   empty => 0, fmt => sub {
            my $c = tuwf->dbRowi('SELECT id, title FROM', charst, 'c WHERE id =', \$_);
            a_ href => "/$c->{id}", title => $c->{title}[1], $c->{id}
        } ],
        [ main_spoil => 'Spoiler',       fmt => sub { txt_ fmtspoil $_ } ],
        [ image      => 'Image',         fmt => sub { image_ $_ } ],
        [ vns        => 'Visual novels', fmt => sub {
            a_ href => "/$_->{vid}", tlang(@{$_->{title}}[0,1]), title => $_->{title}[1], $_->{vid};
            if($_->{rid}) {
                txt_ ' ['; a_ href => "/$_->{rid}", $_->{rid}; txt_ ']';
            }
            txt_ " $CHAR_ROLE{$_->{role}}{txt} (".fmtspoil($_->{spoil}).')';
        } ],
        [ traits => 'Traits', fmt => sub {
            small_ "$_->{groupname} / " if $_->{group} ne $_->{tid};
            a_ href => "/$_->{tid}", $_->{name};
            txt_ ' ('.fmtspoil($_->{spoil}).($_->{lie} ? ', lie':'').')';
            b_ ' (awaiting moderation)' if $_->{hidden} && !$_->{locked};
            b_ ' (trait deleted)' if $_->{hidden} && $_->{locked};
            b_ ' (not applicable)' if !$_->{applicable};
        } ],
}


# Also used by Chars::VNTab
sub chartable_ {
    my($c, $link, $sep, $vn) = @_;
    my $view = viewget;

    my @visvns = grep $_->{spoil} <= $view->{spoilers}, $c->{vns}->@*;

    div_ class => 'chardetails', $sep ? ('+', 'charsep') : (), sub {
        div_ class => 'charimg', sub { image_ $c->{image}, alt => $c->{title}[1] };
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub { td_ colspan => 2, sub {
                $link
                ? a_ href => "/$c->{id}", style => 'margin-right: 10px; font-weight: bold', tlang($c->{title}[0], $c->{title}[1]), $c->{title}[1]
                : span_ style => 'margin-right: 10px', tlang($c->{title}[0], $c->{title}[1]), $c->{title}[1];
                small_ style => 'margin-right: 10px', tlang($c->{title}[2], $c->{title}[3]), $c->{title}[3] if $c->{title}[3] ne $c->{title}[1];

                charsex_ $c->{sex}, $c->{gender} if $c->{sex} || defined $c->{gender};
                if($view->{spoilers} == 2 && (defined $c->{spoil_sex} || defined $c->{spoil_gender})) {
                    txt_ '(';
                    charsex_ $c->{spoil_sex}//$c->{sex}, $c->{spoil_gender}//$c->{gender};
                    spoil_ 2;
                    txt_ ')';
                }
                span_ $BLOOD_TYPE{$c->{bloodt}} if $c->{bloodt} ne 'unknown';
                debug_ $c;
            }}};

            tr_ sub {
                td_ class => 'key', 'Aliases';
                td_ $c->{alias} =~ s/\n/, /rg;
            } if $c->{alias};

            tr_ sub {
                td_ class => 'key', 'Measurements';
                td_ join ', ',
                    $c->{height} ? "Height: $c->{height}cm" : (),
                    defined($c->{weight}) ? "Weight: $c->{weight}kg" : (),
                    $c->{s_bust} || $c->{s_waist} || $c->{s_hip} ?
                    sprintf 'Bust-Waist-Hips: %s-%s-%scm', $c->{s_bust}||'??', $c->{s_waist}||'??', $c->{s_hip}||'??' : (),
                    $c->{cup_size} ? "$CUP_SIZE{$c->{cup_size}} cup" : ();
            } if defined($c->{weight}) || $c->{height} || $c->{s_bust} || $c->{s_waist} || $c->{s_hip} || $c->{cup_size};

            tr_ sub {
                td_ class => 'key', 'Birthday';
                td_ fmtbirthday $c->{birthday};
            } if $c->{birthday};

            tr_ sub {
                td_ class => 'key', 'Age';
                td_ $c->{age};
            } if defined $c->{age};

            my @groups;
            for(grep !$_->{hidden} && ($_->{override}//$_->{spoil}) <= $view->{spoilers} && (!$_->{sexual} || $view->{traits_sexual}), $c->{traits}->@*) {
                push @groups, $_ if !@groups || $groups[$#groups]{group} ne $_->{group};
                push $groups[$#groups]{traits}->@*, $_;
            }
            tr_ class => "trait_group_$_->{group}", sub {
                td_ class => 'key', sub { a_ href => "/$_->{group}", $_->{groupname} };
                td_ sub { join_ ', ', sub {
                    a_ href => "/$_->{tid}",
                        class => $_->{color} && $_->{color} =~ /standout|grayedout/ ? $_->{color} : undef,
                        '+'   => $_->{lie} && (($_->{override}//1) <= 0 || $view->{spoilers} >= 2) ? 'lie' : undef,
                        style => ($_->{color}//'') =~ /^#/ ? "color: $_->{color}" : undef,
                        $_->{name};
                    spoil_ $_->{spoil};
                }, $_->{traits}->@* };
            } for @groups;

            tr_ sub {
                td_ class => 'key', $vn ? 'Releases' : 'Visual novels';
                td_ sub {
                    my @vns;
                    for(@visvns) {
                        push @vns, $_ if !@vns || $vns[$#vns]{vid} ne $_->{vid};
                        push $vns[$#vns]{rels}->@*, $_;
                    }
                    join_ \&br_, sub {
                        my $v = $_;
                        # Just a VN link, no releases
                        if(!$vn && $v->{rels}->@* == 1 && !$v->{rels}[0]{rid}) {
                            txt_ $CHAR_ROLE{$v->{role}}{txt}.' - ';
                            a_ href => "/$v->{vid}", tattr $v;
                            spoil_ $v->{spoil};
                        # With releases
                        } else {
                            a_ href => "/$v->{vid}", tattr $v if !$vn;
                            br_ if !$vn;
                            join_ \&br_, sub {
                                small_ '> ';
                                txt_ $CHAR_ROLE{$_->{role}}{txt}.' - ';
                                if($_->{rid}) {
                                    small_ "$_->{rid}:";
                                    a_ href => "/$_->{rid}", tattr $_->{rtitle};
                                } else {
                                    txt_ 'All other releases';
                                }
                                spoil_ $_->{spoil};
                            }, $v->{rels}->@*;
                        }
                    }, @vns;
                };
            } if @visvns && (!$vn || $vn && (@visvns > 1 || $visvns[0]{rid}));

            tr_ sub {
                td_ class => 'key', 'Voiced by';
                td_ sub {
                    join_ \&br_, sub {
                        a_ href => "/$_->{id}", tattr $_;
                        txt_ " ($_->{note})" if $_->{note};
                    }, $c->{seiyuu}->@*;
                };
            } if $c->{seiyuu}->@*;

            tr_ class => 'nostripe', sub {
                td_ colspan => 2, class => 'chardesc', sub {
                    h2_ 'Description';
                    p_ sub { lit_ bb_format $c->{description}, replacespoil => $view->{spoilers} != 2, keepspoil => $view->{spoilers} == 2 };
                };
            } if $c->{description};

        };
    };
    clearfloat_;

    my %visvns = map +($_->{vid}, 1), @visvns;
    my @quotes = grep $visvns{$_->{vid}}, $c->{quotes}->@*;
    div_ class => 'charquotes', sub {
        h2_ 'Quotes';
        table_ sub {
            tr_ sub {
                td_ sub { VNWeb::VN::Quotes::votething_($_) };
                td_ $_->{quote};
            } for @quotes;
        };
    } if @quotes;
}


TUWF::get qr{/$RE{crev}} => sub {
    my $c = db_entry tuwf->captures('id','rev');
    return tuwf->resNotFound if !$c;

    enrich_item $c;
    enrich_seiyuu undef, $c;
    my $view = viewget;

    my $inst_maxspoil = tuwf->dbVali('SELECT MAX(main_spoil) FROM chars WHERE NOT hidden AND main IN', [ $c->{id}, $c->{main}||() ]);

    my $inst = !defined($inst_maxspoil) || ($c->{main} && $c->{main_spoil} > $view->{spoilers}) ? []
        : fetch_chars undef, sql
            # If this entry doesn't have a 'main', look for other entries with a 'main' referencing this entry
            !$c->{main} ? ('main =', \$c->{id}, 'AND main_spoil <=', \$view->{spoilers}) :
            # Otherwise, look for other entries with the same 'main', and also fetch the 'main' entry itself
            ('(id <>', \$c->{id}, 'AND main =', \$c->{main}, 'AND main_spoil <=', \$view->{spoilers}, ') OR id =', \$c->{main});

    my $max_spoil = max(
        $inst_maxspoil||0,
        (map $_->{override}//($_->{lie}?2:$_->{spoil}), grep !$_->{hidden} && !(($_->{override}//0) == 3), $c->{traits}->@*),
        (map $_->{spoil}, $c->{vns}->@*),
        defined $c->{spoil_sex} || defined $c->{spoil_gender} ? 2 : 0,
        $c->{description} =~ /\[spoiler\]/i ? 2 : 0, # crude
    );
    # Only display the sexual traits toggle when there are sexual traits within the current spoiler level.
    my $has_sex = grep !$_->{hidden} && $_->{sexual} && ($_->{override}//$_->{spoil}) <= $view->{spoilers}, map $_->{traits}->@*, $c, @$inst;

    $c->{title} = titleprefs_swap tuwf->dbVali('SELECT c_lang FROM chars WHERE id =', \$c->{id}), @{$c}{qw/ name latin /};
    framework_ title => $c->{title}[1], index => !tuwf->capture('rev'), dbobj => $c, hiddenmsg => 1,
        og => {
            description => bb_format($c->{description}, text => 1),
            image => $c->{image} && $c->{image}{votecount} && !$c->{image}{sexual} && !$c->{image}{violence} ? imgurl($c->{image}{id}) : undef,
        },
    sub {
        _rev_ $c if tuwf->capture('rev');
        article_ sub {
            itemmsg_ $c;
            h1_ tlang(@{$c->{title}}[0,1]), $c->{title}[1];
            h2_ class => 'alttitle', tlang(@{$c->{title}}[2,3]), $c->{title}[3] if $c->{title}[3] && $c->{title}[3] ne $c->{title}[1];
            p_ class => 'chardetailopts', sub {
                if($max_spoil) {
                    a_ class => $view->{spoilers} == 0 ? 'checked' : undef, href => '?view='.viewset(spoilers=>0, traits_sexual => $view->{traits_sexual}), 'Hide spoilers';
                    a_ class => $view->{spoilers} == 1 ? 'checked' : undef, href => '?view='.viewset(spoilers=>1, traits_sexual => $view->{traits_sexual}), 'Show minor spoilers';
                    a_ class => $view->{spoilers} == 2 ? 'standout': undef, href => '?view='.viewset(spoilers=>2, traits_sexual => $view->{traits_sexual}), 'Spoil me!' if $max_spoil == 2;
                }
                small_ ' | ' if $has_sex && $max_spoil;
                a_ class => $view->{traits_sexual} ? 'checked' : undef, href => '?view='.viewset(spoilers => $view->{spoilers}, traits_sexual=>!$view->{traits_sexual}), 'Show sexual traits' if $has_sex;
            };
            chartable_ $c;
        };

        article_ sub {
            h1_ 'Other instances';
            chartable_ $_, 1, $_ != $inst->[0] for @$inst;
        } if @$inst;
    };
};

1;
