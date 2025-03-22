package VNWeb::Releases::Lib;

use VNWeb::Prelude;
use Exporter 'import';

our @EXPORT = qw/$RELSCHEMA releases_by_vn enrich_release sort_releases release_row_/;


# Common schema to pass around basic release info
our $RELSCHEMA = {
    id        => { vndbid => 'r' },
    title     => {},
    alttitle  => { default => '' },
    released  => { uint => 1 },
    rtype     => {},
    reso_x    => { uint => 1 },
    reso_y    => { uint => 1 },
    lang      => { elems => {} },
    platforms => { elems => {} },
};


# Return the list of releases associated with a VN in the format described by $RELSCHEMA.
sub releases_by_vn($id, %opt) {
    my $l = tuwf->dbAlli('
        SELECT r.id, x.rtype, r.title[1+1] AS title, r.title[1+1+1+1] AS alttitle, r.released, r.reso_x, r.reso_y
          FROM ', releasest, 'r
          JOIN (
            SELECT id, MIN(rtype)
              FROM releases_vn
             WHERE vid IN', ref $id ? $id : [$id],
                   $opt{charlink} ? "AND rtype <> 'trial'" : (), '
             GROUP BY id
           ) x(id,rtype) ON x.id = r.id
         WHERE NOT r.hidden', $opt{charlink} ? "AND r.official" : (), '
         ORDER BY r.released, r.sorttitle, r.id
    ');
    enrich_flatten lang => id => id => sub { sql('SELECT id, lang FROM releases_titles WHERE id IN', $_, 'ORDER BY lang') }, $l;
    enrich_flatten platforms => id => id => sub { sql('SELECT id, platform FROM releases_platforms WHERE id IN', $_, 'ORDER BY platform') }, $l;
    $l
}


# Enrich a list of releases so that it's suitable for release_row_().
# Does not call enrich_vislinks(), which is also needed for release_row_().
# Assumption: Each release already has id, patch, released.
sub enrich_release {
    my($r) = @_;
    enrich_merge id => sql(
        'SELECT id, title, olang, notes, minage, official, freeware, has_ero, reso_x, reso_y, voiced, uncensored
              , ani_story, ani_ero, ani_story_sp, ani_story_cg, ani_cutscene, ani_ero_sp, ani_ero_cg, ani_face, ani_bg
          FROM', releasest, 'r WHERE id IN'), $r;
    enrich_merge id => sub { sql 'SELECT id, MAX(rtype) AS rtype FROM releases_vn WHERE id IN', $_, 'GROUP BY id' }, grep !$_->{rtype}, ref $r ? @$r : $r;
    enrich_merge id => sql('SELECT rid as id, status as rlist_status FROM rlists WHERE uid =', \auth->uid, 'AND rid IN'), $r if auth;
    enrich_flatten platforms => id => id => sub { sql 'SELECT id, platform FROM releases_platforms WHERE id IN', $_, 'ORDER BY id, platform' }, $r;
    enrich titles => id => id => sub { 'SELECT id, lang, mtl, title, latin FROM releases_titles WHERE id IN', $_, 'ORDER BY id, mtl, lang' }, $r;
    enrich media => id => id => sub { 'SELECT id, medium, qty FROM releases_media WHERE id IN', $_, 'ORDER BY id, medium' }, $r;
    enrich drm => id => id => sub { 'SELECT r.id, r.drm, r.notes, d.name,', sql_comma(keys %DRM_PROPERTY), 'FROM releases_drm r JOIN drm d ON d.id = r.drm WHERE r.id IN', $_, 'ORDER BY r.id, r.drm' }, $r;
}


# Sort an array of releases, assumes the objects come from enrich_release()
# (Not always possible with an SQL ORDER BY due to rtype being context-dependent and platforms coming from other tables)
sub sort_releases {
    return [ sort {
        $a->{released} <=> $b->{released} ||
        $b->{rtype} cmp $a->{rtype} ||
        $b->{official} cmp $a->{official} ||
        $a->{patch} cmp $b->{patch} ||
        ($a->{platforms}[0]||'') cmp ($b->{platforms}[0]||'') ||
        $a->{title}[1] cmp $b->{title}[1] ||
        idcmp($a->{id}, $b->{id})
    } $_[0]->@* ];
}


sub release_vislinks_($r) {
    return if !$r->{vislinks}->@*;
    return if !($r->{patch} || $r->{official} || !grep $_->{mtl}, $r->{titles}->@*);

    my $website = (grep $_->{name} eq 'website', $r->{vislinks}->@*)[0];

    return a_ href => $website->{url2}, sub {
        abbr_ class => 'icon-external', title => 'Official website', '';
    } if $r->{vislinks}->@* == 1 && $website;

    a_ href => $website ? $website->{url2} : '#', sub {
        txt_ scalar $r->{vislinks}->@*;
        abbr_ class => 'icon-external', title => 'External link', '';
    };
    div_ sub {
        ul_ sub {
            li_ sub {
                a_ href => $_->{url2}, sub {
                    span_ $_->{price} if length $_->{price};
                    txt_ $_->{label};
                }
            } for $r->{vislinks}->@*;
        }
    }
}


# Options
#   id:   unique identifier if the same release may be listed on a page twice.
#   lang: $lang, whether to display language icons and which language to use for the title and MTL flag.
#   prod: 0/1 whether to display Pub/Dev indication
sub release_row_ {
    my($r, $opt) = @_;

    my $lang = $opt->{lang} && (grep $_->{lang} eq $opt->{lang}, $r->{titles}->@*)[0];
    my $mtl = $lang ? $lang->{mtl} : (grep $_->{mtl}, $r->{titles}->@*) == $r->{titles}->@*;

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
        $class = $class ? " icon-rel-$class" : '';
        abbr_ class => "icon-rel-$img$class", title => $label, '';
    }

    my sub icons_ {
        my($r) = @_;
        icon_ 'notes', bb_format $r->{notes}, text => 1 if $r->{notes};
        icon_ $MEDIUM{ $r->{media}[0]{medium} }{icon}, join ', ', map fmtmedia($_->{medium}, $_->{qty}), $r->{media}->@* if $r->{media}->@*;
        if($r->{reso_y}) {
            my $ratio = $r->{reso_x} / $r->{reso_y};
            my $type = $ratio == 4/3 ? '43' : $ratio == 16/9 ? '169' : 'custom';
            # Ugly workaround: PC-98 has non-square pixels, thus not widescreen
            $type = '43' if $ratio > 4/3 && grep $_ eq 'p98', $r->{platforms}->@*;
            icon_ "reso-$type", resolution $r;
        }
        icon_ 'free', 'Freeware' if $r->{freeware};
        icon_ 'nonfree', 'Non-free' if !$r->{freeware};
        icon_ 'ani-ero', "Erotic scene animation:\n$eroani", "a$r->{ani_ero}" if $r->{ani_ero};
        icon_ 'ani-story', "Story scene animation:\n$storyani", "a$r->{ani_story}" if $r->{ani_story};
        icon_ 'voiced', $VOICED{$r->{voiced}}{txt}, "v$r->{voiced}" if $r->{voiced};
    }

    tr_ $mtl ? (class => 'mtl') : (), sub {
        td_ class => 'tc1', sub { rdate_ $r->{released} };
        td_ class => 'tc2', sub {
            span_ class => 'releaseero releaseero_'.(!$r->{has_ero} ? 'no' : $r->{uncensored} ? 'unc' : defined $r->{uncensored} ? 'cen' : 'yes'),
                  title => !$r->{has_ero} ? 'No erotic scenes' :
                         $r->{uncensored} ? 'Contains uncensored erotic scenes'
               : defined $r->{uncensored} ? 'Contains erotic scenes with optical censoring' : 'Contains erotic scenes', '♥';
            txt_ !$r->{minage} ? 'All' : minage $r->{minage} if defined $r->{minage};
        };
        td_ class => 'tc3', sub {
            platform_ $_ for $r->{platforms}->@*;
            if(!$opt->{lang}) {
                abbr_ class => "icon-lang-$_->{lang}".($_->{mtl}?' mtl':''), title => $LANGUAGE{$_->{lang}}{txt}, '' for $r->{titles}->@*;
            }
            abbr_ class => "icon-rt$r->{rtype}", title => $r->{rtype}, '';
        };
        td_ class => 'tc4', sub {
            my $title =
                $lang && defined $lang->{title} ? titleprefs_obj $lang->{lang}, [$lang] :
                                          $lang ? titleprefs_obj $r->{olang}, [grep $_->{lang} eq $r->{olang}, $r->{titles}->@*]
                                                : $r->{title};
            a_ href => "/$r->{id}", tattr $title;
            my $note = join ' ', $r->{official} ? () : 'unofficial', $mtl ? 'machine translation' : (), $r->{patch} ? 'patch' : ();
            small_ " ($note)" if $note;
            if ($r->{drm}->@*) {
                my($free,$drm);
                for my $d ($r->{drm}->@*) {
                    ${ (grep $d->{$_}, keys %DRM_PROPERTY)[0] ? \$drm : \$free } = 1
                }
                my $nfo = join "\n", map $_->{name}.($_->{notes} ? ' ('.bb_format($_->{notes}, text => 1).')' : ''), $r->{drm}->@*;
                ($free && $drm ? \&span_ : $drm ? \&b_ : \&small_)->(title => $nfo, $free && !$drm ? ' (drm-free)' : ' (drm)');
            }
        };
        td_ class => 'tc_icons', sub { icons_ $r };
        td_ class => 'tc_prod', join ' & ', $r->{publisher} ? 'Pub' : (), $r->{developer} ? 'Dev' : () if $opt->{prod};
        td_ class => 'tc_rlist', auth ? widget(UListRelDD => { id => $r->{id}, status => $r->{rlist_status} }) : (), '';
        td_ class => 'tc_links', sub { release_vislinks_ $r };
    }
}

1;
