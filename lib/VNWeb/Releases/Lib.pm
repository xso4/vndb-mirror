package VNWeb::Releases::Lib;

use VNWeb::Prelude;
use Exporter 'import';

our @EXPORT = qw/enrich_release_elm releases_by_vn enrich_release release_row_/;


# Enrich a list of releases so that it's suitable as 'Releases' Elm response.
# Given objects must have 'id' and 'rtype' fields (appropriate for the VN in context).
sub enrich_release_elm {
    enrich_merge id => 'SELECT id, title, original, released, reso_x, reso_y FROM releases WHERE id IN', @_;
    enrich_flatten lang => id => id => sub { sql('SELECT id, lang FROM releases_lang WHERE id IN', $_, 'ORDER BY lang') }, @_;
    enrich_flatten platforms => id => id => sub { sql('SELECT id, platform FROM releases_platforms WHERE id IN', $_, 'ORDER BY platform') }, @_;
}

# Return the list of releases associated with a VN in the format suitable as 'Releases' Elm response.
sub releases_by_vn {
    my($id) = @_;
    my $l = tuwf->dbAlli('SELECT r.id, rv.rtype FROM releases r JOIN releases_vn rv ON rv.id = r.id WHERE NOT r.hidden AND rv.vid =', \$id, 'ORDER BY r.released, r.title, r.id');
    enrich_release_elm $l;
    $l
}


# Enrich a list of releases so that it's suitable for release_row_().
# Assumption: Each release already has id, patch, released, gtin and enrich_extlinks().
sub enrich_release {
    my($r) = @_;
    enrich_merge id =>
        'SELECT id, title, original, notes, minage, official, freeware, has_ero, reso_x, reso_y, voiced, uncensored
              , ani_story, ani_ero, ani_story_sp, ani_story_cg, ani_cutscene, ani_ero_sp, ani_ero_cg, ani_face, ani_bg
          FROM releases WHERE id IN', $r;
    enrich_merge id => sub { sql 'SELECT id, MAX(rtype) AS rtype FROM releases_vn WHERE id IN', $_, 'GROUP BY id' }, grep !$_->{rtype}, ref $r ? @$r : $r;
    enrich_merge id => sql('SELECT rid as id, status as rlist_status FROM rlists WHERE uid =', \auth->uid, 'AND rid IN'), $r if auth;
    enrich_flatten platforms => id => id => sub { sql 'SELECT id, platform FROM releases_platforms WHERE id IN', $_, 'ORDER BY id, platform' }, $r;
    enrich lang => id => id => sub { 'SELECT id, lang, mtl FROM releases_lang WHERE id IN', $_, 'ORDER BY id, mtl, lang' }, $r;
    enrich media => id => id => sub { 'SELECT id, medium, qty FROM releases_media WHERE id IN', $_, 'ORDER BY id, medium' }, $r;
}


sub release_extlinks_ {
    my($r, $id) = @_;
    return if !$r->{extlinks}->@*;

    if($r->{extlinks}->@* == 1 && $r->{website}) {
        a_ href => $r->{extlinks}[0][1], sub {
            abbr_ class => 'icons external', title => 'Official website', '';
        };
        return
    }

    div_ class => 'elm_dd_noarrow elm_dd_hover elm_dd_left elm_dd_relextlink', sub {
        div_ class => 'elm_dd', sub {
            a_ href => $r->{website}||'#', sub {
                txt_ scalar $r->{extlinks}->@*;
                abbr_ class => 'icons external', title => 'External link', '';
            };
            div_ sub {
                div_ sub {
                    ul_ sub {
                        li_ sub {
                            a_ href => $_->[1], sub {
                                span_ $_->[2] if length $_->[2];
                                txt_ $_->[0];
                            }
                        } for $r->{extlinks}->@*;
                    }
                }
            }
        }
    }
}


# Options
#   id:   unique identifier if the same release may be listed on a page twice.
#   lang: $lang, whether to display language icons and which language to use for the MTL flag.
#   prod: 0/1 whether to display Pub/Dev indication
sub release_row_ {
    my($r, $opt) = @_;

    my $mtl = $opt->{lang}
        ? [grep $_->{lang} eq $opt->{lang}, $r->{lang}->@*]->[0]{mtl}
        : (grep $_->{mtl}, $r->{lang}->@*) == $r->{lang}->@*;

    my $storyani = join "\n", map "$_.",
        $r->{ani_story} == 1 ? 'Not animated' :
        defined $r->{ani_story_sp} || defined $r->{ani_story_cg} || defined $r->{ani_cutscene} || defined $r->{ani_bg} || defined $r->{ani_face} ? (
            defined $r->{ani_story_sp} ? fmtanimation $r->{ani_story_sp}, 'sprites' : (),
            defined $r->{ani_story_cg} ? fmtanimation $r->{ani_story_cg}, 'CGs' : (),
            defined $r->{ani_cutscene} ? fmtanimation $r->{ani_cutscene}, 'cutscenes' : (),
            defined $r->{ani_bg}   ? ($r->{ani_bg} ? 'Animated background effects' : 'No background effects') : (),
            defined $r->{ani_face} ? ($r->{ani_face} ? 'Lip and/or eye movement' : 'No facial animations') : (),
        ) : $ANIMATED{$r->{ani_story}}{txt};

    my $eroani = join "\n", map "$_.",
        $r->{ani_ero} == 1 ? 'Not animated' :
        defined $r->{ani_ero_sp} || defined $r->{ani_ero_cg} ? (
            defined $r->{ani_ero_sp} ? fmtanimation $r->{ani_ero_sp}, 'sprites' : (),
            defined $r->{ani_ero_cg} ? fmtanimation $r->{ani_ero_cg}, 'CGs' : (),
        ) : $ANIMATED{$r->{ani_ero}}{txt};

    my sub icon_ {
        my($img, $label, $class) = @_;
        $class = $class ? " release_icon_$class" : '';
        img_ src => config->{url_static}."/f/$img.svg", class => "release_icons$class", title => $label;
    }

    my sub icons_ {
        my($r) = @_;
        icon_ 'voiced', $VOICED{$r->{voiced}}{txt}, "voiced$r->{voiced}" if $r->{voiced};
        icon_ 'story_animated', "Story scene animation:\n$storyani", "anim$r->{ani_story}" if $r->{ani_story};
        icon_ 'ero_animated', "Erotic scene animation:\n$eroani", "anim$r->{ani_ero}" if $r->{ani_ero};
        icon_ 'free', 'Freeware' if $r->{freeware};
        icon_ 'nonfree', 'Non-free' if !$r->{freeware};
        if($r->{reso_y}) {
            my $ratio = $r->{reso_x} / $r->{reso_y};
            my $type = $ratio == 4/3 ? '4-3' : $ratio == 16/9 ? '16-9' : 'custom';
            # Ugly workaround: PC-98 has non-square pixels, thus not widescreen
            $type = '4-3' if $ratio > 4/3 && grep $_ eq 'p98', $r->{platforms}->@*;
            icon_ "resolution_$type", resolution $r;
        }
        icon_ $MEDIUM{ $r->{media}[0]{medium} }{icon}, join ', ', map fmtmedia($_->{medium}, $_->{qty}), $r->{media}->@* if $r->{media}->@*;
        icon_ 'notes', bb_format $r->{notes}, text => 1 if $r->{notes};
    }

    tr_ $mtl ? (class => 'mtl') : (), sub {
        td_ class => 'tc1', sub { rdate_ [grep $_->{lang} eq $opt->{lang}, $opt->{lang}?$r->{lang}->@*:()]->[0]{released}//$r->{released} };
        td_ class => 'tc2', sub {
            txt_ defined $r->{minage} ? minage $r->{minage} : '';
            icon_ 'ero',
                $r->{uncensored} ? 'Contains uncensored erotic scenes' : defined $r->{uncensored} ? 'Contains erotic scenes with optical censoring' : 'Contains erotic scenes',
                $r->{uncensored} ? 'erounc' : defined $r->{uncensored} ? 'erocen' : '' if $r->{has_ero};
        };
        td_ class => 'tc3', sub {
            platform_ $_ for $r->{platforms}->@*;
            if(!$opt->{lang}) {
                abbr_ class => "icons lang $_->{lang}".($_->{mtl}?' mtl':''), title => $LANGUAGE{$_->{lang}}, '' for $r->{lang}->@*;
            }
            abbr_ class => "icons rt$r->{rtype}", title => $r->{rtype}, '';
        };
        td_ class => 'tc4', sub {
            a_ href => "/$r->{id}", title => $r->{original}||$r->{title}, $r->{title};
            my $note = join ' ', $r->{official} ? () : 'unofficial', $mtl ? 'machine translation' : (), $r->{patch} ? 'patch' : ();
            b_ class => 'grayedout', " ($note)" if $note;
        };
        td_ class => 'tc_icons', sub { icons_ $r };
        td_ class => 'tc_prod', join ' & ', $r->{publisher} ? 'Pub' : (), $r->{developer} ? 'Dev' : () if $opt->{prod};
        td_ class => 'tc5 elm_dd_left', sub {
            elm_ 'UList.ReleaseEdit', $VNWeb::ULists::Elm::RLIST_STATUS, { rid => $r->{id}, uid => auth->uid, status => $r->{rlist_status}, empty => '--' } if auth;
        };
        td_ class => 'tc6', sub { release_extlinks_ $r, "$opt->{id}_$r->{id}" };
    }
}

1;
