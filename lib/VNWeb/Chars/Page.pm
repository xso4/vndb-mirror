package VNWeb::Chars::Page;

use VNWeb::Prelude;
use VNWeb::Images::Lib qw/image_ enrich_image_obj/;


sub enrich_seiyuu {
    my($vid, @chars) = @_;
    enrich seiyuu => id => cid => sub { sql '
        SELECT DISTINCT vs.cid, sa.id, sa.name, sa.original, vs.note
          FROM vn_seiyuu vs
          ', $vid ? () : ('JOIN vn v ON v.id = vs.id'), '
          JOIN staff_alias sa ON sa.aid = vs.aid
         WHERE ', $vid ? ('vs.id =', \$vid) : ('NOT v.hidden'), 'AND vs.cid IN', $_, '
         ORDER BY sa.name'
    }, @chars;
}


sub enrich_item {
    my($c) = @_;

    enrich_image_obj image => $c;
    enrich_merge vid => 'SELECT id AS vid, title, alttitle, c_released AS vn_released FROM vnt WHERE id IN', $c->{vns};
    enrich_merge rid => 'SELECT id AS rid, title AS rtitle, original AS roriginal, released AS rel_released FROM releases WHERE id IN', grep $_->{rid}, $c->{vns}->@*;
    enrich_merge tid =>
     'SELECT t.id AS tid, t.name, t.hidden, t.locked, t.applicable, t.sexual, coalesce(g.id, t.id) AS group, coalesce(g.name, t.name) AS groupname, coalesce(g.order,0) AS order
        FROM traits t LEFT JOIN traits g ON t.group = g.id WHERE t.id IN', $c->{traits};

    $c->{vns}    = [ sort { $a->{vn_released} <=> $b->{vn_released} || ($a->{rel_released}||0) <=> ($b->{rel_released}||0)
                          || $a->{title} cmp $b->{title} || idcmp($a->{vid}, $b->{vid}) || idcmp($a->{rid}||'r999999', $b->{rid}||'r999999') } $c->{vns}->@* ];
    $c->{traits} = [ sort { $a->{order} <=> $b->{order} || $a->{groupname} cmp $b->{groupname} || $a->{name} cmp $b->{name} } $c->{traits}->@* ];
}


# Fetch multiple character entries with a format suitable for chartable_()
# Also used by Chars::VNTab.
sub fetch_chars {
    my($vid, $where) = @_;
    my $l = tuwf->dbAlli('
        SELECT id, name, original, alias, "desc", gender, spoil_gender, b_month, b_day, s_bust, s_waist, s_hip, height, weight, bloodt, cup_size, age, image
          FROM chars WHERE NOT hidden AND (', $where, ')
         ORDER BY name
    ');

    enrich vns => id => id => sub { sql '
        SELECT cv.id, cv.vid, cv.rid, cv.spoil, cv.role, v.title, v.alttitle, r.title AS rtitle, r.original AS roriginal
          FROM chars_vns cv
          JOIN vnt v ON v.id = cv.vid
          LEFT JOIN releases r ON r.id = cv.rid
         WHERE cv.id IN', $_, $vid ? ('AND cv.vid =', \$vid) : (), '
         ORDER BY v.title, cv.vid, cv.rid NULLS LAST'
    }, $l;

    enrich traits => id => id => sub { sql '
        SELECT ct.id, ct.tid, ct.spoil, t.name, t.hidden, t.locked, t.sexual, coalesce(g.id, t.id) AS group, coalesce(g.name, t.name) AS groupname, coalesce(g.order,0) AS order
          FROM chars_traits ct
          JOIN traits t ON t.id = ct.tid
          LEFT JOIN traits g ON t.group = g.id
         WHERE ct.id IN', $_, '
         ORDER BY g.order NULLS FIRST, coalesce(g.name, t.name), t.name'
    }, $l;

    enrich_seiyuu $vid, $l;
    enrich_image_obj image => $l;
    $l
}


sub _rev_ {
    my($c) = @_;
    revision_ $c, \&enrich_item,
        [ name       => 'Name'           ],
        [ original   => 'Original name'  ],
        [ alias      => 'Aliases'        ],
        [ desc       => 'Description'    ],
        [ gender     => 'Sex',           fmt => \%GENDER ],
        [ spoil_gender=> 'Sex (spoiler)',fmt => \%GENDER ],
        [ b_month    => 'Birthday/month',empty => 0 ],
        [ b_day      => 'Birthday/day',  empty => 0 ],
        [ s_bust     => 'Bust',          empty => 0 ],
        [ s_waist    => 'Waist',         empty => 0 ],
        [ s_hip      => 'Hips',          empty => 0 ],
        [ height     => 'Height',        empty => 0 ],
        [ weight     => 'Weight',        ],
        [ bloodt     => 'Blood type',    fmt => \%BLOOD_TYPE ],
        [ cup_size   => 'Cup size',      fmt => \%CUP_SIZE ],
        [ age        => 'Age',           ],
        [ main       => 'Instance of',   empty => 0, fmt => sub {
            my $c = tuwf->dbRowi('SELECT id, name, original FROM chars WHERE id =', \$_);
            a_ href => "/$c->{id}", title => $c->{name}, $c->{id}
        } ],
        [ main_spoil => 'Spoiler',       fmt => sub { txt_ fmtspoil $_ } ],
        [ image      => 'Image',         fmt => sub { image_ $_ } ],
        [ vns        => 'Visual novels', fmt => sub {
            a_ href => "/$_->{vid}", title => $_->{alttitle}||$_->{title}, $_->{vid};
            if($_->{rid}) {
                txt_ ' ['; a_ href => "/$_->{rid}", $_->{rid}; txt_ ']';
            }
            txt_ " $CHAR_ROLE{$_->{role}}{txt} (".fmtspoil($_->{spoil}).')';
        } ],
        [ traits => 'Traits', fmt => sub {
            b_ class => 'grayedout', "$_->{groupname} / " if $_->{group} ne $_->{tid};
            a_ href => "/$_->{tid}", $_->{name};
            txt_ ' ('.fmtspoil($_->{spoil}).')';
            b_ class => 'standout', ' (awaiting moderation)' if $_->{hidden} && !$_->{locked};
            b_ class => 'standout', ' (trait deleted)' if $_->{hidden} && $_->{locked};
            b_ class => 'standout', ' (not applicable)' if !$_->{applicable};
        } ],
}


# Also used by Chars::VNTab
sub chartable_ {
    my($c, $link, $sep, $vn) = @_;
    my $view = viewget;

    div_ mkclass(chardetails => 1, charsep => $sep), sub {
        div_ class => 'charimg', sub { image_ $c->{image}, alt => $c->{name} };
        table_ class => 'stripe', sub {
            thead_ sub { tr_ sub { td_ colspan => 2, sub {
                $link
                ? a_ href => "/$c->{id}", style => 'margin-right: 10px; font-weight: bold', $c->{name}
                : b_ style => 'margin-right: 10px', $c->{name};
                b_ class => 'grayedout', style => 'margin-right: 10px', $c->{original} if $c->{original};
                abbr_ class => "icons gen $c->{gender}", title => $GENDER{$c->{gender}}, '' if $c->{gender} ne 'unknown';
                if($view->{spoilers} == 2 && defined $c->{spoil_gender}) {
                    txt_ '(';
                    abbr_ class => "icons gen $c->{spoil_gender}", title => $GENDER{$c->{spoil_gender}}, '' if $c->{spoil_gender} ne 'unknown';
                    txt_ 'unknown' if $c->{spoil_gender} eq 'unknown';
                    spoil_ 2;
                    txt_ ')';
                }
                span_ $BLOOD_TYPE{$c->{bloodt}} if $c->{bloodt} ne 'unknown';
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
                td_ $c->{b_day}.' '.[qw{January February March April May June July August September October November December}]->[$c->{b_month}-1];
            } if $c->{b_day} && $c->{b_month};

            tr_ sub {
                td_ class => 'key', 'Age';
                td_ $c->{age};
            } if defined $c->{age};

            my @groups;
            for(grep !$_->{hidden} && $_->{spoil} <= $view->{spoilers} && (!$_->{sexual} || $view->{traits_sexual}), $c->{traits}->@*) {
                push @groups, $_ if !@groups || $groups[$#groups]{group} ne $_->{group};
                push $groups[$#groups]{traits}->@*, $_;
            }
            tr_ class => "trait_group_$_->{group}", sub {
                td_ class => 'key', sub { a_ href => "/$_->{group}", $_->{groupname} };
                td_ sub { join_ ', ', sub { a_ href => "/$_->{tid}", $_->{name}; spoil_ $_->{spoil} }, $_->{traits}->@* };
            } for @groups;

            my @visvns = grep $_->{spoil} <= $view->{spoilers}, $c->{vns}->@*;
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
                            a_ href => "/$v->{vid}", title => $v->{alttitle}||$v->{title}, $v->{title};
                            spoil_ $v->{spoil};
                        # With releases
                        } else {
                            a_ href => "/$v->{vid}", title => $v->{alttitle}||$v->{title}, $v->{title} if !$vn;
                            br_ if !$vn;
                            join_ \&br_, sub {
                                b_ class => 'grayedout', '> ';
                                txt_ $CHAR_ROLE{$_->{role}}{txt}.' - ';
                                if($_->{rid}) {
                                    b_ class => 'grayedout', "$_->{rid}:";
                                    a_ href => "/$_->{rid}", title => $_->{roriginal}||$_->{rtitle}, $_->{rtitle};
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
                        a_ href => "/$_->{id}", title => $_->{original}||$_->{name}, $_->{name};
                        txt_ " ($_->{note})" if $_->{note};
                    }, $c->{seiyuu}->@*;
                };
            } if $c->{seiyuu}->@*;

            tr_ class => 'nostripe', sub {
                td_ colspan => 2, class => 'chardesc', sub {
                    h2_ 'Description';
                    p_ sub { lit_ bb_format $c->{desc}, replacespoil => $view->{spoilers} != 2, keepspoil => $view->{spoilers} == 2 };
                };
            } if $c->{desc};
        };
    };
    clearfloat_;
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
        (map $_->{spoil}, grep !$_->{hidden}, $c->{traits}->@*),
        (map $_->{spoil}, $c->{vns}->@*),
        defined $c->{spoil_gender} ? 2 : 0,
        $c->{desc} =~ /\[spoiler\]/i ? 2 : 0, # crude
    );
    # Only display the sexual traits toggle when there are sexual traits within the current spoiler level.
    my $has_sex = grep !$_->{hidden} && $_->{spoil} <= $view->{spoilers} && $_->{sexual}, map $_->{traits}->@*, $c, @$inst;

    framework_ title => $c->{name}, index => !tuwf->capture('rev'), dbobj => $c, hiddenmsg => 1,
        og => {
            description => bb_format($c->{desc}, text => 1),
            image => $c->{image} && $c->{image}{votecount} && !$c->{image}{sexual} && !$c->{image}{violence} ? imgurl($c->{image}{id}) : undef,
        },
    sub {
        _rev_ $c if tuwf->capture('rev');
        div_ class => 'mainbox', sub {
            itemmsg_ $c;
            h1_ sub { txt_ $c->{name}; debug_ $c };
            h2_ class => 'alttitle', $c->{original} if length $c->{original};
            p_ class => 'chardetailopts', sub {
                if($max_spoil) {
                    a_ mkclass(checked => $view->{spoilers} == 0), href => '?view='.viewset(spoilers=>0, traits_sexual => $view->{traits_sexual}), 'Hide spoilers';
                    a_ mkclass(checked => $view->{spoilers} == 1), href => '?view='.viewset(spoilers=>1, traits_sexual => $view->{traits_sexual}), 'Show minor spoilers';
                    a_ mkclass(standout =>$view->{spoilers} == 2), href => '?view='.viewset(spoilers=>2, traits_sexual => $view->{traits_sexual}), 'Spoil me!' if $max_spoil == 2;
                }
                b_ class => 'grayedout', ' | ' if $has_sex && $max_spoil;
                a_ mkclass(checked => $view->{traits_sexual}), href => '?view='.viewset(spoilers => $view->{spoilers}, traits_sexual=>!$view->{traits_sexual}), 'Show sexual traits' if $has_sex;
            };
            chartable_ $c;
        };

        div_ class => 'mainbox', sub {
            h1_ 'Other instances';
            chartable_ $_, 1, $_ != $inst->[0] for @$inst;
        } if @$inst;
    };
};

1;
