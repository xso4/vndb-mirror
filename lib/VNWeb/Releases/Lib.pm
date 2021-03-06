package VNWeb::Releases::Lib;

use VNWeb::Prelude;
use Exporter 'import';

our @EXPORT = qw/enrich_release_elm releases_by_vn enrich_release release_row_/;


# Enrich a list of releases so that it's suitable as 'Releases' Elm response.
sub enrich_release_elm {
    enrich_merge id => 'SELECT id, title, original, released, type as rtype, reso_x, reso_y FROM releases WHERE id IN', @_;
    enrich_flatten lang => id => id => sub { sql('SELECT id, lang FROM releases_lang WHERE id IN', $_, 'ORDER BY lang') }, @_;
    enrich_flatten platforms => id => id => sub { sql('SELECT id, platform FROM releases_platforms WHERE id IN', $_, 'ORDER BY platform') }, @_;
}

# Return the list of releases associated with a VN in the format suitable as 'Releases' Elm response.
sub releases_by_vn {
    my($id) = @_;
    my $l = tuwf->dbAlli('SELECT r.id FROM releases r JOIN releases_vn rv ON rv.id = r.id WHERE NOT r.hidden AND rv.vid =', \$id, 'ORDER BY r.released, r.title, r.id');
    enrich_release_elm $l;
    $l
}


# Enrich a list of releases so that it's suitable for release_row_().
# Assumption: Each release already has id, type, patch, released, gtin and enrich_extlinks().
sub enrich_release {
    my($r) = @_;
    enrich_merge id => 'SELECT id, title, original, notes, minage, official, freeware, doujin, reso_x, reso_y, voiced, ani_story, ani_ero, uncensored FROM releases WHERE id IN', $r;
    enrich_merge id => sql('SELECT rid as id, status as rlist_status FROM rlists WHERE uid =', \auth->uid, 'AND rid IN'), $r if auth;
    enrich_flatten lang => id => id => sub { sql 'SELECT id, lang FROM releases_lang WHERE id IN', $_, 'ORDER BY id, lang' }, $r;
    enrich_flatten platforms => id => id => sub { sql 'SELECT id, platform FROM releases_platforms WHERE id IN', $_, 'ORDER BY id, platform' }, $r;
    enrich media => id => id => sub { 'SELECT id, medium, qty FROM releases_media WHERE id IN', $_, 'ORDER BY id, medium' }, $r;
}


sub release_extlinks_ {
    my($r, $id) = @_;
    return if !$r->{extlinks}->@*;

    if($r->{extlinks}->@* == 1 && $r->{website}) {
        a_ href => $r->{website}, sub {
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
#   lang: 0/1 whether to display language icons
#   prod: 0/1 whether to display Pub/Dev indication
sub release_row_ {
    my($r, $opt) = @_;

    my sub icon_ {
        my($img, $label, $class) = @_;
        $class = $class ? " release_icon_$class" : '';
        img_ src => config->{url_static}."/f/$img.svg", class => "release_icons$class", title => $label;
    }

    my sub icons_ {
        my($r) = @_;
        icon_ 'voiced', $VOICED{$r->{voiced}}{txt}, "voiced$r->{voiced}" if $r->{voiced};
        icon_ 'story_animated', "Story: $ANIMATED{$r->{ani_story}}{txt}", "anim$r->{ani_story}" if $r->{ani_story};
        icon_ 'ero_animated', "Ero: $ANIMATED{$r->{ani_ero}}{txt}", "anim$r->{ani_ero}" if $r->{ani_ero};
        icon_ 'free', 'Freeware' if $r->{freeware};
        icon_ 'nonfree', 'Non-free' if !$r->{freeware};
        icon_ 'doujin', 'Doujin' if !$r->{patch} && $r->{doujin};
        icon_ 'commercial', 'Commercial' if !$r->{patch} && !$r->{doujin};
        if($r->{reso_y}) {
            my $ratio = $r->{reso_x} / $r->{reso_y};
            my $type = $ratio == 4/3 ? '4-3' : $ratio == 16/9 ? '16-9' : 'custom';
            # Ugly workaround: PC-98 has non-square pixels, thus not widescreen
            $type = '4-3' if $ratio > 4/3 && grep $_ eq 'p98', $r->{platforms}->@*;
            icon_ "resolution_$type", resolution $r;
        }
        icon_ $MEDIUM{ $r->{media}[0]{medium} }{icon}, join ', ', map fmtmedia($_->{medium}, $_->{qty}), $r->{media}->@* if $r->{media}->@*;
        icon_ 'uncensor', 'Uncensored' if $r->{uncensored};
        icon_ 'notes', bb_format $r->{notes}, text => 1 if $r->{notes};
    }

    tr_ sub {
        td_ class => 'tc1', sub { rdate_ $r->{released} };
        td_ class => 'tc2', defined $r->{minage} ? minage $r->{minage} : '';
        td_ class => 'tc3', sub {
            abbr_ class => "icons plat $_", title => $PLATFORM{$_}, '' for $r->{platforms}->@*;
            if($opt->{lang}) {
                abbr_ class => "icons lang $_", title => $LANGUAGE{$_}, '' for $r->{lang}->@*;
            }
            abbr_ class => "icons rt$r->{type}", title => $r->{type}, '';
        };
        td_ class => 'tc4', sub {
            a_ href => "/$r->{id}", title => $r->{original}||$r->{title}, $r->{title};
            my $note = join ' ', $r->{official} ? () : 'unofficial', $r->{patch} ? 'patch' : ();
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
